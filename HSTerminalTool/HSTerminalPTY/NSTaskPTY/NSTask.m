//
//  NSTask.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "NSTask.h"
#import <util.h>

@implementation NSTask (PTY)
- (NSFileHandle *)masterSideOfPTYOrError:(NSError *__autoreleasing *)error {
    char *pName=NULL;
    int fdMaster, fdSlave;
    char sptyname[20];
    int rc = openpty(&fdMaster, &fdSlave, sptyname, NULL, NULL);
    if (rc != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return NULL;
    }else{
        pName = ptsname(fdMaster);//get slave device name, the arg is the master device
        printf("Name of slave side is <%s>    fd = %d\n", pName, fdSlave);
         
        strcpy(sptyname, pName);
        printf("my sptyname is %s\n",sptyname);
    }
    fcntl(fdMaster, F_SETFD, FD_CLOEXEC);
    fcntl(fdSlave, F_SETFD, FD_CLOEXEC);
    NSFileHandle *masterHandle = [[NSFileHandle alloc] initWithFileDescriptor:fdMaster closeOnDealloc:YES];
    NSFileHandle *slaveHandle = [[NSFileHandle alloc] initWithFileDescriptor:fdSlave closeOnDealloc:YES];
    self.standardInput = slaveHandle;
    self.standardOutput = slaveHandle;
    return masterHandle;
}
@end
