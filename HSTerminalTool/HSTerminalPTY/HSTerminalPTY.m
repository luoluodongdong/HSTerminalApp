//
//  HSTerminalPTY.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "HSTerminalPTY.h"
#import <util.h>
#import "NSTask.h"

#define RECV_LOOP_WAIT      0.001

typedef void (^data_available_handler)(NSString *str);

@interface HSTerminalPTY()

@property (strong) NSPipe *stdinPipe;
@property (strong) NSPipe *stdoutPipe;
@property (strong) NSPipe *stderrPipe;

@property (strong) NSTask *operateTask;
@property (strong) dispatch_semaphore_t busySem;

/* dispatch_io objects handling async read of both pipes */
@property (strong) dispatch_io_t stdoutIO;
@property (strong) dispatch_io_t stderrIO;

/* buffers to store incoming text from the telnet task */
@property (strong) NSMutableString *stdoutBuf;
@property (assign) BOOL stdoutShouldBuffer;

/* serial queues to ensure sequential processing of data */
@property (strong) dispatch_queue_t stdoutQueue;
@property (strong) dispatch_queue_t stderrQueue;
@property (strong) NSFileHandle *slaveHandle;
@property (strong) NSFileHandle *masterHandle;
@end

@implementation HSTerminalPTY

- (id)init
{
    self = [super init];

    if (self) {
        //_url         = nil;
        //_telnetTask  = nil;

        _stdoutBuf   = [NSMutableString new];
        _stdoutQueue = dispatch_queue_create("com.apple.hwte.telnetstdout", DISPATCH_QUEUE_SERIAL);
        _stderrQueue = dispatch_queue_create("com.apple.hwte.telnetstderr", DISPATCH_QUEUE_SERIAL);
        _busySem     = dispatch_semaphore_create(1);

        //_lineSeparator      = @"\n";
        _stdoutShouldBuffer = NO;
        _ptyListener     = nil;
    }

    return self;
}

-(void)dealloc
{
    [self close];
}
-(BOOL)launchMyPTY:(NSError **)err{
    //-----------------openpty----------
    char *pName=NULL;
    int fdMaster, fdSlave;
    char sptyname[20];
    int rc = openpty(&fdMaster, &fdSlave, sptyname, NULL, NULL);
    if (rc != 0) {
        NSLog(@"openpty operate fail!");
        if (err) {
            *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return NO;
    }else{
        pName = ptsname(fdMaster);//get slave device name, the arg is the master device
        printf("Name of slave side is <%s>    fd = %d\n", pName, fdSlave);
         
        strcpy(sptyname, pName);
        printf("my sptyname is %s\n",sptyname);
        //test write to mpty and read from spty*************
        char temp[50] = {"hell\n"};
        char temp2[100];
        ssize_t c = write(fdMaster,temp,5);
        if(c <=0)
                printf("ERROR : can not write to mpty\n");
        sleep(3);
        printf("write %zd charactors to mpty success\n",c);
        sleep(3);
        printf("try to read from spty\n");
        sleep(3);
        ssize_t c2 = read(fdSlave,temp2,5);
        if(c2 <=0)
                printf("ERROR : can not read from mpty\n");
        printf("read from spty  %zd charactors success\n",c2);
        printf("\n>>>>>  %s  <<<<<\n\n___________________\n",temp2);
    }
    fcntl(fdMaster, F_SETFD, FD_CLOEXEC);
    fcntl(fdSlave, F_SETFD, FD_CLOEXEC);
    self.masterHandle = [[NSFileHandle alloc] initWithFileDescriptor:fdMaster closeOnDealloc:YES];
    self.slaveHandle = [[NSFileHandle alloc] initWithFileDescriptor:fdSlave closeOnDealloc:YES];
    
    if (!self.masterHandle) {
        NSLog(@"error: could not set up PTY for task!");
        return NO;
    }
    return YES;
}
-(BOOL)connectPTYClosedHandler:(void (^)(NSError *))closed_handler error:(NSError **)err{
    if ([self.operateTask isRunning]) {
        NSLog(@"task already running");
        *err = [NSError errorWithDomain:@"task already running" code:0 userInfo:nil];
        return NO;
    }
    
    //---------------------------
    
    self.stdinPipe  = [NSPipe pipe];
    self.stdoutPipe = [NSPipe pipe];
    self.stderrPipe = [NSPipe pipe];

    /* launch the telnet task */
    self.operateTask = [NSTask new];
    [self.operateTask setLaunchPath:self.launchPath];
    NSError *error;
    self.masterHandle = [self.operateTask masterSideOfPTYOrError:&error];
    if (!self.masterHandle) {
        NSLog(@"error: could not set up PTY for task: %@", error);
        return NO;
    }
    [self.operateTask setArguments:@[@"--login",@"-i"]];
    //[self.telnetTask setArguments:@[self.url.host, [self.url.port stringValue]]];
    
    //self.operateTask.standardInput = self.slaveHandle;
    //self.operateTask.standardOutput = self.slaveHandle;

    //[self.operateTask setStandardInput:self.stdinPipe];
    //[self.operateTask setStandardOutput:self.stdoutPipe];
    [self.operateTask setStandardError:self.stderrPipe];
    
    self.operateTask.terminationHandler = ^(NSTask *aTask){
        /* do our own teardown for connection closed */
        NSLog(@"Termination handler.");

        NSError *err = [NSError errorWithDomain:@"telnet process died" code:0 userInfo:nil];
        closed_handler(err);
    };

    /* TODO: wait until connected or timeout, and return appropriately */

    //int stdout_fd = [[self.stdoutPipe fileHandleForReading] fileDescriptor];
    int stdout_fd = [self.masterHandle fileDescriptor];
    int stderr_fd = [[self.stderrPipe fileHandleForReading] fileDescriptor];

    self.stdoutIO = kickoff_dispatch_io(stdout_fd, self.stdoutQueue, ^(NSString *str) {
        [self.ptyListener receiveStandardOutData:str];
        if (self.stdoutShouldBuffer) {
            [self.stdoutBuf appendString:str];
        }
    });

    self.stderrIO = kickoff_dispatch_io(stderr_fd, self.stderrQueue, ^(NSString *str) {
        [self.ptyListener receiveStandardErrorData:str];
    });

    [self.operateTask launch];
    
    //[self.slaveHandle writeData:[@"help\n" dataUsingEncoding:NSUTF8StringEncoding]];

    return YES;
}
-(void)disconnectPTY{
    [self close];
}
-(BOOL)sendMessage:(NSString *)message{
    [self.masterHandle writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
//    sleep(1);
//    NSData *data = [self.slaveHandle readDataToEndOfFile];
//    NSLog(@"read data:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return YES;
    
    if (![self prepare_to_send]) {
            return false;
        }

    //    if ([str hasSuffix:self.lineSeparator] == false) {
    //        str = [str stringByAppendingString:self.lineSeparator];
    //    }

        [[self.stdinPipe fileHandleForWriting] writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
        [self.ptyListener receiveStandardInData:message];
    double timeo = 2.0;
    NSString *response = @"";
    
        NSError *err = nil;
        //NSRegularExpression *expr = [NSRegularExpression regularExpressionWithPattern:regex_str options:0 error:&err];

        if (err) {
            //NSLog( @"RegExp '%@' is not valid: (%@) -> Will read from connection until timeout", err, regex_str);
            [NSThread sleepForTimeInterval:timeo];

            __block NSString *recv_str;
            dispatch_sync(self.stdoutQueue, ^{
                recv_str = [NSString stringWithString:self.stdoutBuf];
            });

            response = recv_str;

            [self command_finish_cleanup];
            return true;
        }

        __block bool matched = false;
        __block NSString *recv_str;

        timeo = MAX(timeo, 0);
        NSDate *expire = [NSDate dateWithTimeIntervalSinceNow:timeo];
        NSLog(@"Using timeout of %.3lf", timeo);

        do
        {
            [NSThread sleepForTimeInterval:RECV_LOOP_WAIT]; /* pace ourselves here, no need to spin in a tight loop */

            dispatch_sync(self.stdoutQueue, ^{
//                NSTextCheckingResult *regex_match = [expr firstMatchInString:self.stdoutBuf options:0 range:NSMakeRange(0, recv_str.length)];
//                if (regex_match) {
//                    matched = true;
//                }
                matched = true;
                recv_str = [NSString stringWithString:self.stdoutBuf];
            });

        } while (!matched && [expire timeIntervalSinceNow] > 0);

        response = recv_str;

        [self command_finish_cleanup];
    
    NSLog(@"response:%@",response);

        return matched;
}
- (bool)prepare_to_send
{
    if (!self.operateTask.isRunning) {
        return false;
    }

    /* try to decrement the semaphore; return if it is already held */
    if (dispatch_semaphore_wait(self.busySem, DISPATCH_TIME_NOW) != 0){
        return false;
    }

    dispatch_sync(self.stdoutQueue, ^{
        [self.stdoutBuf setString:@""];
        self.stdoutShouldBuffer = YES;
    });

    return true;
}

- (void)command_finish_cleanup
{
    dispatch_sync(self.stdoutQueue, ^{
        self.stdoutShouldBuffer = NO;
    });

    dispatch_semaphore_signal(self.busySem);
}

- (void)close
{
    if (self.operateTask.isRunning) {
        NSLog(@"Closing operateTask.");
        [self.operateTask terminate];
        self.operateTask = nil;
    }
}


#pragma mark -
#pragma mark dispatch_io helper calls


NSData *data_from_dispatch_data(dispatch_data_t data)
{
    NSMutableData *retval = [NSMutableData data];

    dispatch_data_apply(data, ^(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
        [retval appendBytes:buffer length:size];
        return (bool)true;
    });

    return retval;
}

dispatch_io_t
kickoff_dispatch_io(int fd, dispatch_queue_t process_queue, data_available_handler data_handler)
{

    /* TODO: remove closing handler (present for debug only) */
    /* TODO: can we pass null in as the queue instead? */
    dispatch_io_t retval = dispatch_io_create(DISPATCH_IO_STREAM, fd, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(int err){
        NSLog(@"dispatch_io is closed");
    });

    dispatch_io_set_low_water(retval, 1);
    //dispatch_io_set_interval(self.ioChannel, 0, 0);

    dispatch_io_handler_t io_handler = ^(bool done, dispatch_data_t data, int error){
        if (done || error != 0){
            NSLog(@"dispatch_io_handler_t terminating");
            return;
        }

        NSData *raw_data = data_from_dispatch_data(data);
        NSString *str = [[NSString alloc] initWithData:raw_data encoding:NSUTF8StringEncoding];

        /* dispatch the data handler onto the user-specified queue (to allow serialization of processing) */
        dispatch_async(process_queue, ^{
            data_handler(str);
        });

    };

    /* kickoff a read which will go to EOF. */
    dispatch_io_read(retval, 0, SIZE_MAX, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), io_handler);

    return retval;
}

@end
