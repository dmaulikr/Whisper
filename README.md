# MCOneToOne #

A singleton / passive-connection / one-to-one / thread-aware / data sending relationship built on top of Multipeer Connectivity written in Objective-C. 

## Sample Usage ##

```
#!objective-c

// Builds  
[[MCOneToOne connection] setDelegate:self];
[[MCOneToOne connection] startAndConnectWithService:@"mc-hammer"];

#pragma mark - MCOneToOne Delegate:

// It's your responsibility to track your users, MCOneToOne will connect passively upon any 
-(void)didChangeConnectionStatusForPeer:(MCPeerID*)peer {

}
```