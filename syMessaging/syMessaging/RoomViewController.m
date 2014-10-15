/*
 Copyright 2014 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "RoomViewController.h"

#import "MatrixHandler.h"
#import "AppDelegate.h"

// Table view cell
@interface RoomMessageCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *userPicture;
@property (weak, nonatomic) IBOutlet UITextView  *messageTextView;
@end
@implementation RoomMessageCell
@end

@interface IncomingMessageCell : RoomMessageCell
@end
@implementation IncomingMessageCell
@end

@interface OutgoingMessageCell : RoomMessageCell
@end
@implementation OutgoingMessageCell
@end


@interface RoomViewController ()
{
    BOOL isFirstDisplay;
    
    MXRoomData *mxRoomData;
    
    NSMutableArray *messages;
    id registeredListener;
}

@property (weak, nonatomic) IBOutlet UINavigationItem *roomNavItem;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIView *controlView;
@property (weak, nonatomic) IBOutlet UIButton *optionBtn;
@property (weak, nonatomic) IBOutlet UITextField *messageTextField;
@property (weak, nonatomic) IBOutlet UIButton *sendBtn;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *controlViewBottomConstraint;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;

@end

@implementation RoomViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    isFirstDisplay = YES;
    
    _sendBtn.enabled = NO;
    _sendBtn.alpha = 0.5;
}

- (void)dealloc {
    messages = nil;
    if (registeredListener) {
        [mxRoomData unregisterListener:registeredListener];
        registeredListener = nil;
    }
    mxRoomData = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Reload room data
    [self configureView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onTextFieldChange:) name:UITextFieldTextDidChangeNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (registeredListener) {
        [mxRoomData unregisterListener:registeredListener];
        registeredListener = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (isFirstDisplay) {
        // Scroll to the bottom
        [self scrollToBottomAnimated:animated];
        isFirstDisplay = NO;
    }
}

#pragma mark -

- (void)setRoomId:(NSString *)roomId {
    _roomId = roomId;
    
    // Load room data
    [self configureView];
}

#pragma mark - Internal methods

- (void)configureView {
    // Flush messages
    messages = nil;
    
    // Remove potential roomData listener
    if (registeredListener && mxRoomData) {
        [mxRoomData unregisterListener:registeredListener];
        registeredListener = nil;
    }
    
    // Update room data
    if (self.roomId) {
        mxRoomData = [[MatrixHandler sharedHandler].mxData getRoomData:self.roomId];
        messages = [NSMutableArray arrayWithArray:mxRoomData.messages];
        // Register a listener for all events
        registeredListener = [mxRoomData registerEventListenerForTypes:nil block:^(MXRoomData *roomData, MXEvent *event, BOOL isLive) {
            // consider only live event
            if (isLive) {
                // For outgoing message, remove the temporary event
                if ([event.user_id isEqualToString:[MatrixHandler sharedHandler].userId]) {
                    NSUInteger index = messages.count;
                    while (index--) {
                        MXEvent *mxEvent = [messages objectAtIndex:index];
                        if ([mxEvent.event_id isEqualToString:event.event_id]) {
                            [messages replaceObjectAtIndex:index withObject:event];
                            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                            return;
                        }
                    }
                }
                // Here a new event is added
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:messages.count inSection:0];
                [messages addObject:event];
                [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
                [self scrollToBottomAnimated:YES];
            }
        }];
    } else {
        mxRoomData = nil;
    }
    
    [self.tableView reloadData];
    
    // Update room title
    self.roomNavItem.title = mxRoomData.displayname;
}

- (void)onKeyboardWillShow:(NSNotification *)notif {
    NSValue *rectVal = notif.userInfo[UIKeyboardFrameEndUserInfoKey];
    CGRect endRect = rectVal.CGRectValue;
    
    UIEdgeInsets insets = self.tableView.contentInset;
    // Handle portrait/landscape mode
    insets.bottom = (endRect.origin.y == 0) ? endRect.size.width : endRect.size.height;
    self.tableView.contentInset = insets;
    
    [self scrollToBottomAnimated:YES];
    
    // Move up control view
    // Don't forget the offset related to tabBar
    _controlViewBottomConstraint.constant = insets.bottom - [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height;
}

- (void)onKeyboardWillHide:(NSNotification *)notif {
    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = self.controlView.frame.size.height;
    self.tableView.contentInset = insets;
    
    _controlViewBottomConstraint.constant = 0;
}

- (void)dismissKeyboard {
    // Hide the keyboard
    [_messageTextField resignFirstResponder];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    // Scroll table view to the bottom
    NSInteger rowNb = messages.count;
    if (rowNb) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(rowNb - 1) inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Default message cell height
    CGFloat rowHeight = 50;
    
    return rowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)aTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RoomMessageCell *cell;
    MatrixHandler *mxHandler = [MatrixHandler sharedHandler];
    MXEvent *mxEvent = [messages objectAtIndex:indexPath.row];
    
    if ([mxEvent.user_id isEqualToString:mxHandler.userId]) {
        cell = [aTableView dequeueReusableCellWithIdentifier:@"OutgoingMessageCell" forIndexPath:indexPath];
    } else {
        cell = [aTableView dequeueReusableCellWithIdentifier:@"IncomingMessageCell" forIndexPath:indexPath];
    }
    
    cell.messageTextView.text = [mxHandler displayTextFor:mxEvent inDetailMode:NO];    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Dismiss keyboard when user taps on table view content
    [self dismissKeyboard];
}

// Detect vertical bounce at the top of the tableview to trigger pagination
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView == self.tableView) {
        // paginate ?
        if ((scrollView.contentOffset.y < -64) && (_activityIndicator.isAnimating == NO))
        {
            if (mxRoomData.canPaginate)
            {
                [_activityIndicator startAnimating];
                
                [mxRoomData paginateBackMessages:20 success:^(NSArray *oldMessages) {
                    // Update messages array
                    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, oldMessages.count)];
                    [messages insertObjects:oldMessages atIndexes:indexSet];
                    
                    // Refresh display
                    [self.tableView beginUpdates];
                    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:oldMessages.count];
                    for (NSUInteger index = 0; index < oldMessages.count; index++) {
                        [indexPaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
                    }
                    [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
                    [self.tableView endUpdates];
                    
                    // Maintain the current message in visible area
                    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(oldMessages.count - 1) inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
                    [_activityIndicator stopAnimating];
                } failure:^(NSError *error) {
                    [_activityIndicator stopAnimating];
                    NSLog(@"Failed to paginate back: %@", error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            }
        }
    }
}

#pragma mark - UITextField delegate

- (void)onTextFieldChange:(NSNotification *)notif {
    NSString *msg = _messageTextField.text;
    
    if (msg.length) {
        _sendBtn.enabled = YES;
        _sendBtn.alpha = 1;
    } else {
        _sendBtn.enabled = NO;
        _sendBtn.alpha = 0.5;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField*) textField {
    // "Done" key has been pressed
    [textField resignFirstResponder];
    return YES;
}

#pragma mark -

- (IBAction)onButtonPressed:(id)sender {
    if (sender == _sendBtn) {
        NSString *msgTxt = self.messageTextField.text;
        
        // Send message to the room
        [[[MatrixHandler sharedHandler] mxSession] postTextMessage:self.roomId text:msgTxt success:^(NSString *event_id) {
            // Create a temporary event to displayed outgoing message
            MXEvent *mxEvent = [[MXEvent alloc] init];
            mxEvent.room_id = self.roomId;
            mxEvent.event_id = event_id;
            mxEvent.eventType = MXEventTypeRoomMessage;
            mxEvent.type = kMXEventTypeStringRoomMessage;
            mxEvent.content = @{@"msgtype":@"m.text", @"body":msgTxt};
            mxEvent.user_id = [MatrixHandler sharedHandler].userId;
            
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:messages.count inSection:0];
            [messages addObject:mxEvent];
            [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
            [self scrollToBottomAnimated:YES];
        } failure:^(NSError *error) {
            NSLog(@"Failed to send message (%@): %@", self.messageTextField.text, error);
            //Alert user
            [[AppDelegate theDelegate] showErrorAsAlert:error];
        }];
        
        self.messageTextField.text = nil;
        // disable send button
        [self onTextFieldChange:nil];
    } else if (sender == _optionBtn) {
        [self dismissKeyboard];
        //TODO: display option menu (Attachments...)
    }
}
@end