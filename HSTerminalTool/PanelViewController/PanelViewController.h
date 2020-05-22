//
//  PanelViewController.h
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

@interface PanelViewController : NSViewController
{
    
    IBOutlet NSTextView *inputTextView;
    IBOutlet NSButton *sendBtn;
    IBOutlet NSButton *clearBtn;
    IBOutlet NSTextView *logTextView;
}

-(IBAction)sendBtnAction:(id)sender;
-(IBAction)clearBtnAction:(id)sender;
@end

NS_ASSUME_NONNULL_END
