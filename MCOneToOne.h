//
//  MCOneToOne.h
//  MCOneToOne
//
//  Created by Eli Gregory on 1/6/15.
//  Copyright (c) 2015 Stublisher Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

typedef enum
{
    ConnectionStatusDisconnected,
    ConnectionStatusInviting,
    ConnectionStatusInvited,
    ConnectionStatusConnecting,
    ConnectionStatusConnected,
    ConnectionStatusLost,
    ConnectionStatusUnknown
}
MCOneToOneConnectionStatus;

@class MCContent;

@protocol MCOneToOneDelegate <NSObject>
@required
-(void)didChangeConnectionStatusForPeer:(MCPeerID*)peer;
-(void)didReceiveContent:(MCContent*)content fromPeer:(MCPeerID*)peer;

@end

/*\
\\\  MCOneToOne : A singleton / fully piped / one-to-one / data sending relationship built on top of Multipeer Connectivity
\*/

@interface MCOneToOne : NSObject <MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate>

+(MCOneToOne*)connection; // singleton

- (void)startAndConnectWithService:(NSString*)serviceKey;
- (void)radar;
- (void)stopAndDisconnect;

- (MCOneToOneConnectionStatus)statusForPeer:(MCPeerID*)peer;

- (void)sendPeer:(MCPeerID*)peer_ content:(MCContent*)content;

+ (NSString*)stringForConnectionStatus:(MCOneToOneConnectionStatus)status;

@property (nonatomic, readonly) NSMutableArray *connectedPeers; // an array of MCPeerIDs
@property (nonatomic) BOOL gracefulBackgrounding;
@property (nonatomic, readonly) NSString *serviceKey;
@property (nonatomic) BOOL forceMainThread;

@property (nonatomic) id <MCOneToOneDelegate> delegate;

@end

/*\
\\\  MCContent : Abstract class to send content through MCOneToOne
\*/

@interface MCContent : NSObject <NSCoding>

+(MCContent*)contentCode:(NSUInteger)code withContent:(id)content; // or nil

@property (nonatomic, readonly) NSUInteger contentCode;
@property (nonatomic, readonly) id content;

@end
