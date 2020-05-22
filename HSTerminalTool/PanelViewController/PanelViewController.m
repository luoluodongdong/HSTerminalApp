//
//  PanelViewController.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "PanelViewController.h"
#import "HSsimplePTY.h"


@interface PanelViewController ()<HSsimplePTYDelegate,NSTextViewDelegate>

@property HSsimplePTY *myPTY;

//@property MyTerminal *myTerminal;

@property dispatch_queue_t printLogQueue;

@end

@implementation PanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    self.printLogQueue = dispatch_queue_create("com.hsterminal.printlogqueue", DISPATCH_QUEUE_SERIAL);
    inputTextView.delegate = self;
    
    self.myPTY = [[HSsimplePTY alloc] init];
    self.myPTY.delegate = self;
    if([self.myPTY startTerminal]){
        //setting terminal window size
        [self.myPTY setWinWidth:120 height:30];
    }
    
}

-(void)dealloc{
    [self.myPTY stopTerminal];
}

-(IBAction)sendBtnAction:(id)sender{
    NSString *cmd = [inputTextView.textStorage string];
    if ([cmd length] == 0) {
        return;
    }
    cmd = [cmd stringByAppendingString:@"\n"];

    [self.myPTY writeCommand:cmd];
    inputTextView.string = @"";
}
-(IBAction)clearBtnAction:(id)sender{
    logTextView.string = @"";
    [self.myPTY writeCommand:@"\n"];
}
#pragma mark - NSTextViewDelegate
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    //insertTab:   -键入tab
    //insertNewline:   -键入回车
    //deleteBackward
    
    if ([NSStringFromSelector(commandSelector) isEqualToString:@"insertNewline:"]) {
        
        if (([NSApplication sharedApplication].currentEvent.modifierFlags & NSEventModifierFlagShift) != 0) {
            //NSLog(@"Shift-Enter detected.");
            [textView insertNewlineIgnoringFieldEditor:self];
            return YES;
        }else {
            //NSLog(@"Enter detected.");
            [sendBtn performClick:nil];
            return YES;
        }
    }
    return NO;
}

#pragma mark -- delegate pipe
- (void)receiveStandardInData:(NSString *)str{
    //NSLog(@"recv in data:%@",str);
}
- (void)receiveStandardOutData:(NSString *)str{
    //NSLog(@"recv out data:%@",str);
    dispatch_async(self.printLogQueue, ^{
        [self performSelectorOnMainThread:@selector(updateLog:) withObject:str waitUntilDone:YES];
    });
}
- (void)receiveStandardErrorData:(NSString *)str{
    //NSLog(@"recv err data:%@",str);
    dispatch_async(self.printLogQueue, ^{
        [self performSelectorOnMainThread:@selector(updateLog:) withObject:str waitUntilDone:YES];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->sendBtn setEnabled:NO];
    });
}

-(void)updateLog:(NSString *)log{
    NSUInteger textLen = self->logTextView.textStorage.length;
        if (textLen > 500000) {
            [self->logTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
        }
        // 设置字体颜色NSForegroundColorAttributeName，取值为 UIColor对象，默认值为黑色
        NSMutableAttributedString *textColor = [[NSMutableAttributedString alloc] initWithString:log];
    //        [textColor addAttribute:NSForegroundColorAttributeName
    //                          value:[NSColor greenColor]
    //                          range:[@"NSAttributedString设置字体颜色" rangeOfString:@"NSAttributedString"]];
        [textColor addAttribute:NSForegroundColorAttributeName
                          value:[NSColor systemGreenColor]
                          range:NSMakeRange(0, log.length)];
        
        //NSAttributedString *attrStr=[[NSAttributedString alloc] initWithString:self.logString];
        textLen = textLen + log.length;
        [self->logTextView.textStorage appendAttributedString:textColor];
        [self->logTextView scrollRangeToVisible:NSMakeRange(textLen,0)];
}
@end
