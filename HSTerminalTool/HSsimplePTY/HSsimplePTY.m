//
//  HSsimplePTY.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/22.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "HSsimplePTY.h"
#import "util.h"
//#import "Darwin.POSIX.ioctl"
#include <sys/ioctl.h>

#define RECV_LOOP_WAIT      0.001

typedef void (^data_available_handler)(NSString *str);

@interface HSsimplePTY()

@property int filedescription;
@property pid_t childPID;
@property NSFileHandle *filehandle;

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

@end

@implementation HSsimplePTY

-(instancetype)init{
    if (self=[super init]) {
        self.childPID = -1;
        self.filehandle = nil;
        self.filedescription = -1;
        
        _stdoutBuf   = [NSMutableString new];
        _stdoutQueue = dispatch_queue_create("com.apple.hwte.telnetstdout", DISPATCH_QUEUE_SERIAL);
        _stderrQueue = dispatch_queue_create("com.apple.hwte.telnetstderr", DISPATCH_QUEUE_SERIAL);
        _busySem     = dispatch_semaphore_create(1);

        //_lineSeparator      = @"\n";
        _stdoutShouldBuffer = NO;
        _delegate     = nil;
    }
    
    return self;
}

-(BOOL)startTerminal{
    self.filedescription = -1;
    //pid_t    forkpty(int *, char *, struct termios *, struct winsize *);
    pid_t pid = forkpty(&_filedescription,nil,nil,nil);
    if (pid == -1) {
        NSLog(@"fork failed: %d: %s", errno, strerror(errno));
        return NO;
    }else if(pid == 0){
        // Handle the child subprocess. First try to use /bin/login since it’s a little nicer. Fall
        // back to /bin/bash if that is available.
        [self autoLogin];
    }else{
        NSLog(@"process forked: %d", pid);
        self.childPID = pid;
        self.filehandle = [[NSFileHandle alloc] initWithFileDescriptor:self.filedescription closeOnDealloc:YES];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
//        [center addObserver:self selector:@selector(didReceivedData:) name:NSFileHandleReadCompletionNotification object:self.filehandle];
//        [self.filehandle readInBackgroundAndNotify];
        [center addObserverForName:@"com.hssimplepty.terminated" object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            //NSLog(@"123321");
            [self stopTerminal];
            //[self.delegate receiveStandardOutData:@"terminal exited\n"];
        }];
        
        self.stdoutIO = kickoff_dispatch_io(self.filedescription, self.stdoutQueue, ^(NSString *str) {
            [self.delegate receiveStandardOutData:str];
            if (self.stdoutShouldBuffer) {
                [self.stdoutBuf appendString:str];
            }
        });

//        self.stderrIO = kickoff_dispatch_io(stderr_fd, self.stderrQueue, ^(NSString *str) {
//            [self.ptyListener receiveStandardErrorData:str];
//        });
    }
    
    return YES;
    
}
-(BOOL)setWinWidth:(int )width height:(int )height{
    struct winsize windowSize; //= winsize();
    windowSize.ws_col = width; //80
    windowSize.ws_row = height; //25

    if(ioctl(_filedescription, TIOCSWINSZ, &windowSize) == -1){
        NSLog(@"setting screen size failed: %d: %s", errno, strerror(errno));
        //delegate!.subProcess(didReceiveError: SubProcessIOError.writeFailed);
    }
    return YES;
}
-(void)autoLogin{
    //NSArray *args1 = @[@"login",@"-fp", NSUserName()];
    NSArray *args2 = @[@"bash",@"--login", @"-i"];
    NSArray *env = @[@"TERM=xterm-color",
                     @"LANG=en_US.UTF-8",
                     @"TERM_PROGRAM=NewTerm",
                     @"LC_TERMINAL=NewTerm"];
    //[self attemptStartProcessPath:@"/usr/bin/login" args:args1 env:env];
    [self attemptStartProcessPath:@"/bin/bash" args:args2 env:env];
}
-(void)writeCommand:(NSString *)cmd{
    //[self.filehandle writeData:cmd];
    if (![self prepare_to_send]) {
        return;
    }
    [self.filehandle writeData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
    [self.delegate receiveStandardInData:cmd];
    
    [self command_finish_cleanup];
}
-(BOOL)query:(NSString *)cmd withRegex:(NSString *)regexStr timeout:(double )to error:(NSError **)err{
    if (![self prepare_to_send]) {
        return NO;
    }
    *err = nil;
    NSRegularExpression *expr = [NSRegularExpression regularExpressionWithPattern:regexStr options:0 error:err];
    if (err != nil) {
        NSLog( @"RegExp '%@' is not valid: (%@) -> Will read from connection until timeout", *err, regexStr);
        return NO;
    }
    [self.filehandle writeData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
    [self.delegate receiveStandardInData:cmd];
    
    __block BOOL matched = NO;
    __block NSString *recv_str;

    to = MAX(to, 0);
    NSDate *expire = [NSDate dateWithTimeIntervalSinceNow:to];
    NSLog(@"Using timeout of %.3lf", to);

    do
    {
        [NSThread sleepForTimeInterval:RECV_LOOP_WAIT]; /* pace ourselves here, no need to spin in a tight loop */
        dispatch_sync(self.stdoutQueue, ^{
            NSTextCheckingResult *regex_match = [expr firstMatchInString:self.stdoutBuf options:0 range:NSMakeRange(0, recv_str.length)];
            if (regex_match) {
                matched = YES;
            }
            recv_str = [NSString stringWithString:self.stdoutBuf];
        });

    } while (!matched && [expire timeIntervalSinceNow] > 0);

    NSString *response = recv_str;
    NSLog(@"response:%@",response);

    [self command_finish_cleanup];
    
    return matched;
}
-(void)stopTerminal{
    if (self.childPID == -1) {
        return;
    }
    kill(self.childPID,SIGKILL);
    
    int stat;
    waitpid(self.childPID, &stat, WUNTRACED);
    
//    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
//    [center removeObserver:self name:NSFileHandleReadCompletionNotification object:self.filehandle];
    
    self.childPID = -1;
    self.filedescription = -1;
    self.filehandle = nil;
    [self.delegate receiveStandardErrorData:@"simple pty disconnected\n"];
}

-(BOOL)attemptStartProcessPath:(NSString *)path args:(NSArray *)args env:(NSArray *)env{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path] == NO) {
        return NO;
    }
    if ([fm isExecutableFileAtPath:path] == NO) {
        return NO;
    }
    const char* pathC = [path cStringUsingEncoding:NSUTF8StringEncoding];
    char** argsC = [self cStringArray:args];
    char** envC = [self cStringArray:env];
    if (execve(pathC, argsC, envC) == -1) {
        NSLog(@"%@: exec failed: %s", path, strerror(errno));
        return NO;
    }
    return YES;
}

- (char **)cStringArray:(NSArray *)array{
    // this is in objc because it’s impossibly complex to do this in Objective-C…
    NSUInteger count = array.count + 1;
    char **result = malloc(sizeof(char *) * count);

    for (NSUInteger i = 0; i < array.count; i++) {
        NSString *item = [array[i] isKindOfClass:NSString.class] ? array[i] : ((NSObject *)array[i]).description;
        result[i] = (char *)item.UTF8String;
    }

    result[count - 1] = NULL;
    return result;
}
//-(void)didReceivedData:(NSNotification *)notification{
//    NSLog(@"12121212");
//    NSData *data = [notification.userInfo objectForKey:NSFileHandleNotificationDataItem];
//    if (data == nil) {
//        NSLog(@"file handle read callback returned nil data");
//        return;
//    }
//    if ([data length] == 0) {
//        NSLog(@"terminal has exited!");
//        return;
//    }
//    NSLog(@"recv data:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//
//    [self.filehandle readInBackgroundAndNotify];
//}

- (bool)prepare_to_send
{
    if (self.filehandle == nil) {
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

dispatch_io_t kickoff_dispatch_io(int fd, dispatch_queue_t process_queue, data_available_handler data_handler)
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
            NSNotificationCenter *center =[NSNotificationCenter defaultCenter];
            NSNotification *notification = [[NSNotification alloc] initWithName:@"com.hssimplepty.terminated" object:nil userInfo:@{@"data":@"terminal closed"}];
            [center postNotification:notification];
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
