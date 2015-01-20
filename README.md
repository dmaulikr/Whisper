# MCOneToOne #

A singleton / passive-connection / one-to-one / thread-aware / data sending relationship built on top of Multipeer Connectivity written in Objective-C. 

## Sample Usage ##

```
#!objective-c
// Establishes singleton, assigns delegate and begins advertising and broadcasting service with string unique to your app.  
[[MCOneToOne connection] setDelegate:self];
[[MCOneToOne connection] startAndConnectWithService:@"mc-hammer"];

_connectedUsers = [NSMutableSet set];

#pragma mark - MCOneToOne Delegate:
// It's your responsibility to track your users, MCOneToOne will build a one to one connection passively upon any discovery or invitation
-(void)didChangeConnectionStatusForPeer:(MCPeerID*)peer {
    // Check the status of peers as they change
    MCOneToOneConnectionStatus status = [[MCOneToOne connection] statusForPeer:peer];

    // Determine what to do for different statuses
    if (status == ConnectionStatusConnected) {
        // send NSObject subtype & assign a content code so the receiver knows what they are receiving
        [[MCOneToOne connection] sendPeer:peer content:[MCContent contentCode:100 withContent:@"Hey!"]];
        [_connectedUsers addObject:peer];
    }
    else {
        if ([_connectedUsers containsObject:peer]) [_connectedUsers removeObject:peer];
    }
}

-(void)didReceiveContent:(MCContent*)content fromPeer:(MCPeerID*)peer {
    // check content code
    if (content.contentCode == 100) {
        // will log "hey!"
        NSLog(@"Recieved message: %@",(NSString*)content.content);
    }
}
```

### Version History: ###
**0.1**
First commit, tested with 3 devices only. 