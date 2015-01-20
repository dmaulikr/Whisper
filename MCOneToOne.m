//
//  MCOneToOne.m
//  MCOneToOne
//
//  Created by Eli Gregory on 1/6/15.
//  Copyright (c) 2015 Stublisher Inc. All rights reserved.
//

#import "MCOneToOne.h"

static NSString * const MCContentEncodedContent     = @"MCContentEncodedContent";
static NSString * const MCContentEncodedContentCode = @"MCContentEncodedContentCode";

static NSString * const MCConnectionWasLost         = @"comm_was_lost";

const float browseTimeout = 5.0f;

 /*\
 \\\  MCOneToOne Private Interface
 \*/

@interface MCOneToOne()
{
    NSMutableDictionary *sessions; // MCSession values for MCPeerID keys
    NSMutableDictionary *status;   // MCOneToOneConnectionStatus values for MCPeerID keys
    
    NSMutableSet *peers;
    
    NSDate *lastPing;
}

@property (nonatomic, strong) MCPeerID *myPeerID;
@property (nonatomic, strong) MCNearbyServiceAdvertiser *advertiser;
@property (nonatomic, strong) MCNearbyServiceBrowser *browser;
@property (nonatomic, readwrite) NSArray *connectedPeers; // an array of MCPeerIDs
@property (nonatomic, readwrite) NSString *serviceKey;
@end

 /*\
 \\\  MCContent Private Interface
 \*/

@interface MCContent()

-(NSData*)encode;
+(MCContent*)decode:(NSData*)data;

@property (nonatomic, readwrite) NSUInteger contentCode;
@property (nonatomic, readwrite) id content;

@end

@implementation MCOneToOne
@synthesize myPeerID = _myPeerID;
@synthesize advertiser = _advertiser;
@synthesize browser = _browser;
@synthesize connectedPeers = _connectedPeers;
@synthesize gracefulBackgrounding = _gracefulBackgrounding;
@synthesize delegate = _delegate;
@synthesize serviceKey = _serviceKey;
@synthesize forceMainThread = _forceMainThread;

+(MCOneToOne*)connection
{
    static dispatch_once_t onceToken;
    __strong static MCOneToOne *c = nil;
    
    dispatch_once(&onceToken, ^
                  {
                      c = [[self alloc] init];
                  });
    return c;
}

-(id)init
{
    self = [super init];
    
    if (self)
    {
        _myPeerID   = [[MCPeerID alloc] initWithDisplayName:[[[UIDevice currentDevice] identifierForVendor] UUIDString]];
        sessions    = [NSMutableDictionary dictionary];
        status      = [NSMutableDictionary dictionary];
        peers       = [NSMutableSet set];
        
        _forceMainThread = TRUE;
        
        [self setGracefulBackgrounding:TRUE];        
    }
    return self;
}

- (void)setupNetworkComm
{
    // Build the service advertiser
    _advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:_myPeerID  discoveryInfo:nil serviceType:_serviceKey];
    [self.advertiser setDelegate:self];
    
    // Build the service browser
    _browser = [[MCNearbyServiceBrowser alloc] initWithPeer:_myPeerID serviceType:_serviceKey];
    [self.browser setDelegate:self];
}

- (void)teardownSessions
{
    // for all sessions, disconnect
    [sessions enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
    {
        MCSession *sesh = (MCSession*)obj;
        [sesh disconnect];
    }];
    
    // clear out dictionaries
    [sessions removeAllObjects];
    [status removeAllObjects];
}

-(MCSession*)sessionForPeer:(MCPeerID*)peerID
{
    MCSession *sesh;
    
    if ([sessions objectForKey:peerID]) sesh = [sessions objectForKey:peerID];
    
    else
    {
        sesh = [[MCSession alloc] initWithPeer:_myPeerID];
        [sesh setDelegate:self];
        
        [sessions setObject:sesh forKey:peerID];
    }
    
    return sesh;
}

-(void)disconnectFromPeer:(MCPeerID*)peerID
{
    MCSession *sesh = [self sessionForPeer:peerID];
    
    if (sesh)
    {
        [sesh disconnect];
        [sessions removeObjectForKey:peerID];
    }
}

- (void)startAndConnectWithService:(NSString*)serviceKey
{
    NSMutableString *errorString = [NSMutableString stringWithString:@">> Can't connect, invalid service key."];
    BOOL isError = FALSE;
    
    if ([serviceKey length] < 1 || [serviceKey length] > 15)
    {
        [errorString appendString:@" Key must be less than 15 characters."];
        isError = TRUE;
    }
            
    if (([[serviceKey componentsSeparatedByString:@"-"] count] - 1) > 1)
    {
        [errorString appendString:@" Key can contain at most one hyphen."];
        isError = TRUE;
    }
    
    if (isError)
    {
        NSLog(@"%@", errorString);
        return;
    }
    
    _serviceKey = serviceKey;
    
    [self setupNetworkComm];
    [self start];
    
    lastPing = [NSDate date];
}

-(void)restartAndConnect
{
    [self startAndConnectWithService:_serviceKey];
}

- (void)radar
{
    if ([[NSDate date] timeIntervalSinceDate:lastPing] > browseTimeout)
    {
        [self stop];
        [self start];
        
        lastPing = [NSDate date];
    }
}

-(void)stop
{
    [self.browser stopBrowsingForPeers];
    [self.advertiser stopAdvertisingPeer];
}

-(void)start
{
    [self.advertiser startAdvertisingPeer];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

        [self.browser startBrowsingForPeers];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, browseTimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            
            [self.browser stopBrowsingForPeers];
        });
    });
}

- (void)stopAndDisconnect
{
    [self stop];
    [self teardownSessions];
    _serviceKey = nil;
}

-(void)stopAndStart
{
    [self stop];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self start];
    });
}

-(MCOneToOneConnectionStatus)statusForPeer:(MCPeerID*)peer
{
    if ([status objectForKey:peer])
    {
        return (MCOneToOneConnectionStatus)[[status objectForKey:peer] integerValue];
    }
    else return ConnectionStatusUnknown;
}

-(void)sendPeer:(MCPeerID*)peer content:(MCContent*)content
{
    MCSession *sesh = [sessions objectForKey:peer];
    
    if (!sesh) return;
    
    NSError *error;
    
    [sesh sendData:[content encode] toPeers:sesh.connectedPeers withMode:MCSessionSendDataReliable error:&error];
    
    if (error)
    {
        // TODO understand error codes & account for all of them
    }
}

-(void)modConnectionStatus:(MCOneToOneConnectionStatus)s forPeer:(MCPeerID*)peer
{
    [status setObject:[NSNumber numberWithInteger:s] forKey:peer];
    
    if ([self.delegate respondsToSelector:@selector(didChangeConnectionStatusForPeer:)])
    {
        [self forceMain:^
        {
            [self.delegate didChangeConnectionStatusForPeer:peer];
        }];
    }
}

#pragma mark - MCNearbyServiceAdvertiserDelegate

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void(^)(BOOL accept, MCSession *session))invitationHandler
{
    NSLog(@">> Recieving Invitation from %@", peerID.displayName);
    
    [peers addObject:peerID];
    
    BOOL shouldAccept = TRUE;
    
    MCOneToOneConnectionStatus peerStatus = [self statusForPeer:peerID];
    
    if (peerStatus == ConnectionStatusInviting ||
        peerStatus == ConnectionStatusInvited ||
        peerStatus == ConnectionStatusConnected ||
        peerStatus == ConnectionStatusConnecting) shouldAccept = FALSE;
    
    if (context)
    {
        if ([[MCOneToOne fromContext:context] isEqualToString:MCConnectionWasLost]) shouldAccept = TRUE;
    }
    
    else [self modConnectionStatus:ConnectionStatusInvited forPeer:peerID];
    
    MCSession *sesh = [self sessionForPeer:peerID];

    if (shouldAccept) invitationHandler(TRUE, sesh);
    else invitationHandler(FALSE, nil);
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error
{
    NSLog(@">> Did not start advertising peer : %@", [error localizedDescription]);
    [self stopAndStart];
}

#pragma mark - MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)b foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    if ([peerID.displayName compare:_myPeerID.displayName] == NSOrderedAscending)
    {
        NSLog(@">> Browser found : %@", peerID.displayName);
        
        [peers addObject:peerID];
                
        BOOL shouldInvite = TRUE;
        
        MCOneToOneConnectionStatus peerStatus = [self statusForPeer:peerID];
        NSData *context = nil;
        
        if (peerStatus == ConnectionStatusInvited ||
            peerStatus == ConnectionStatusInviting ||
            peerStatus == ConnectionStatusConnected ||
            peerStatus == ConnectionStatusConnecting) shouldInvite = FALSE;
        
        if (peerStatus == ConnectionStatusLost) context = [MCOneToOne toContext:MCConnectionWasLost];
        
        if (shouldInvite)
        {
            [self modConnectionStatus:ConnectionStatusInviting forPeer:peerID];
            
            MCSession *sesh = [self sessionForPeer:peerID];
            
            [_browser invitePeer:peerID toSession:sesh withContext:context timeout:30.0];
        }
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
    [self modConnectionStatus:ConnectionStatusLost forPeer:peerID];
    [self disconnectFromPeer:peerID];
    [self stopAndStart];
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error
{
    [self stopAndStart];
}

#pragma mark - MCSessionDelegate

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
{
    MCContent *content = [MCContent decode:data];
    
    if ([self.delegate respondsToSelector:@selector(didReceiveContent:fromPeer:)])
    {
        [self forceMain:^{
            [self.delegate didReceiveContent:content fromPeer:peerID];
        }];
    }
}

- (void) session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL accept))certificateHandler
{
    NSLog(@">> Recieved Certificate: %@", certificate);
    certificateHandler(YES);
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
    switch (state)
    {
        case MCSessionStateConnecting:
        {
            [sessions setObject:session forKey:peerID];
            [self modConnectionStatus:ConnectionStatusConnecting forPeer:peerID];
        }
            break;
            
        case MCSessionStateConnected:
        {
            [sessions setObject:session forKey:peerID];
            [self modConnectionStatus:ConnectionStatusConnected forPeer:peerID];
        }
            break;
            
        case MCSessionStateNotConnected:
        {
            if ([sessions objectForKey:peerID]) [sessions removeObjectForKey:peerID];
            [self modConnectionStatus:ConnectionStatusDisconnected forPeer:peerID];
            [self disconnectFromPeer:peerID];
            [self stopAndStart];
        }
            break;
    }
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
    /* Unsupported */
}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
    /* Unsupported */
}

- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
    /* Unsupported */
}

-(void)setGracefulBackgrounding:(BOOL)gracefulBackgrounding
{
    _gracefulBackgrounding = gracefulBackgrounding;
    
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];

    if (_gracefulBackgrounding)
    {
        [defaultCenter addObserver:self
                          selector:@selector(restartAndConnect)
                              name:UIApplicationWillEnterForegroundNotification
                            object:nil];
        
        [defaultCenter addObserver:self
                          selector:@selector(stopAndDisconnect)
                              name:UIApplicationDidEnterBackgroundNotification
                            object:nil];
    }
    else
    {
        [defaultCenter removeObserver:self
                                 name:UIApplicationWillEnterForegroundNotification
                               object:nil];
        
        [defaultCenter removeObserver:self
                                 name:UIApplicationDidEnterBackgroundNotification
                               object:nil];
    }
}

-(void)forceMain:(void (^)(void))toMain
{
    if ( ![NSThread isMainThread] && _forceMainThread ) dispatch_sync(dispatch_get_main_queue(), toMain);
    else toMain();
}

+(NSString*)stringForConnectionStatus:(MCOneToOneConnectionStatus)status
{
    switch (status) {
        case ConnectionStatusDisconnected: {return @"Disconnected";} break;
        case ConnectionStatusInviting: {return @"Inviting";} break;
        case ConnectionStatusInvited: {return @"Invited";} break;
        case ConnectionStatusConnecting: {return @"Connecting";} break;
        case ConnectionStatusConnected: {return @"Connected";} break;
        case ConnectionStatusLost: {return @"Lost";} break;
        case ConnectionStatusUnknown: {return @"Unknown";} break;
        default: {return @"Unknown";} break;
    }
}

+(NSData*)toContext:(NSString*)string
{
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString*)fromContext:(NSData*)context
{
    return [[NSString alloc] initWithData:context encoding:NSUTF8StringEncoding];
}

@end

@implementation MCContent
@synthesize contentCode =_contentCode;
@synthesize content = _content;

+(MCContent*)contentCode:(NSUInteger)code withContent:(id)content
{    
    return [[MCContent alloc] initWithCode:code andContent:content];
}

-(id)initWithCode:(NSUInteger)code andContent:(id)content
{
    self = [super init];
    
    if (self)
    {
        if (![content isKindOfClass:[NSObject class]]) return nil;
        
        _contentCode = code;
        _content = content;
    }
    return self;
}

-(NSData*)encode
{
    return [NSKeyedArchiver archivedDataWithRootObject:self];
}

+(MCContent*)decode:(NSData *)data
{
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

-(id)initWithCoder:(NSCoder *)decoder
{
    if (self = [super init])
    {
        _contentCode    = [decoder decodeIntegerForKey:MCContentEncodedContentCode];
        _content        = [decoder decodeObjectForKey:MCContentEncodedContent];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:_contentCode forKey:MCContentEncodedContentCode];
    [encoder encodeObject:_content forKey:MCContentEncodedContent];
}
@end
