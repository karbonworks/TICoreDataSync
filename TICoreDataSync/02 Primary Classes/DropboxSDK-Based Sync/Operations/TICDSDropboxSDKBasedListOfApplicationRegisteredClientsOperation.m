//
//  TICDSDropboxSDKBasedListOfApplicationRegisteredClientsOperation.m
//  iOSNotebook
//
//  Created by Tim Isted on 23/05/2011.
//  Copyright 2011 Tim Isted. All rights reserved.
//

#if TARGET_OS_IPHONE

#import "TICoreDataSync.h"


@implementation TICDSDropboxSDKBasedListOfApplicationRegisteredClientsOperation

- (BOOL)needsMainThread
{
    return YES;
}

- (void)fetchArrayOfClientUUIDStrings
{
    [[self restClient] loadMetadata:[self clientDevicesDirectoryPath]];
}

- (void)fetchDeviceInfoDictionaryForClientWithIdentifier:(NSString *)anIdentifier
{
    NSString *path = [[[self clientDevicesDirectoryPath] stringByAppendingPathComponent:anIdentifier] stringByAppendingPathComponent:TICDSDeviceInfoPlistFilenameWithExtension];
    
    [[self restClient] loadFile:path intoPath:[[self tempFileDirectoryPath] stringByAppendingPathComponent:anIdentifier]];
}

- (void)fetchArrayOfDocumentUUIDStrings
{
    [[self restClient] loadMetadata:[self documentsDirectoryPath]];
}

- (void)fetchArrayOfClientsRegisteredForDocumentWithIdentifier:(NSString *)anIdentifier
{
    NSString *path = [[[self documentsDirectoryPath] stringByAppendingPathComponent:anIdentifier] stringByAppendingPathComponent:TICDSSyncChangesDirectoryName];
    
    [[self restClient] loadMetadata:path];
}

#pragma mark - Rest Client Delegate
#pragma mark Metadata
- (void)restClient:(DBRestClient*)client loadedMetadata:(DBMetadata*)metadata
{
    NSString *path = [metadata path];
    
    if( [path isEqualToString:[self clientDevicesDirectoryPath]] ) {
        NSMutableArray *clientIdentifiers = [NSMutableArray arrayWithCapacity:[[metadata contents] count]];
        
        for( DBMetadata *eachSubMetadata in [metadata contents] ) {
            if( ![eachSubMetadata isDirectory] || [eachSubMetadata isDeleted] ) {
                continue;
            }
            
            [clientIdentifiers addObject:[[eachSubMetadata path] lastPathComponent]];
        }
        
        [self fetchedArrayOfClientUUIDStrings:clientIdentifiers];
        
        return;
    }
    
    if( [path isEqualToString:[self documentsDirectoryPath]] ) {
        NSMutableArray *documentIdentifiers = [NSMutableArray arrayWithCapacity:[[metadata contents] count]];
        
        for( DBMetadata *eachSubMetadata in [metadata contents] ) {
            if( ![eachSubMetadata isDirectory] || [eachSubMetadata isDeleted] ) {
                continue;
            }
            
            [documentIdentifiers addObject:[[eachSubMetadata path] lastPathComponent]];
        }
        
        [self fetchedArrayOfDocumentUUIDStrings:documentIdentifiers];
        
        return;
    }
    
    if( [[path lastPathComponent] isEqualToString:TICDSSyncChangesDirectoryName] ) {
        NSMutableArray *clientIdentifiers = [NSMutableArray arrayWithCapacity:[[metadata contents] count]];
        
        for( DBMetadata *eachSubMetadata in [metadata contents] ) {
            if( ![eachSubMetadata isDirectory] || [eachSubMetadata isDeleted] ) {
                continue;
            }
            
            [clientIdentifiers addObject:[[eachSubMetadata path] lastPathComponent]];
        }
        
        [self fetchedArrayOfClients:clientIdentifiers registeredForDocumentWithIdentifier:[[path stringByDeletingLastPathComponent] lastPathComponent]];
        return;
    }
}

- (void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path
{
    
}

- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error
{
    NSString *path = [[error userInfo] valueForKey:@"path"];
    NSInteger errorCode = [error code];
    
    if (errorCode == 503) {
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Encountered an error 503, retrying immediately. %@", path);
        [client loadMetadata:path];
        return;
    }
    
    [self setError:[TICDSError errorWithCode:TICDSErrorCodeDropboxSDKRestClientError underlyingError:error classAndMethod:__PRETTY_FUNCTION__]];
    
    if( [path isEqualToString:[self clientDevicesDirectoryPath]] ) {
        [self fetchedArrayOfClientUUIDStrings:nil ];
        return;
    }
    
    if( [path isEqualToString:[self documentsDirectoryPath]] ) {
        [self fetchedArrayOfDocumentUUIDStrings:nil];
        return;
    }
    
    if( [[path lastPathComponent] isEqualToString:TICDSSyncChangesDirectoryName] ) {
        [self fetchedArrayOfClients:nil registeredForDocumentWithIdentifier:[[path stringByDeletingLastPathComponent] lastPathComponent]];
        return;
    }
}

#pragma mark Loading Files
- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath
{
    NSError *anyError = nil;
    BOOL success = YES;
    
    // Only one file loaded by this operation...
    
    NSString *identifier = [destPath lastPathComponent];
    
    if( [self shouldUseEncryption] ) {
        NSString *tmpPath = [destPath stringByAppendingPathExtension:@"decrypt"];
        
        success = [[self cryptor] decryptFileAtLocation:[NSURL fileURLWithPath:destPath] writingToLocation:[NSURL fileURLWithPath:tmpPath] error:&anyError];
        
        if( !success ) {
            [self setError:[TICDSError errorWithCode:TICDSErrorCodeEncryptionError underlyingError:anyError classAndMethod:__PRETTY_FUNCTION__]];
            [self fetchedDeviceInfoDictionary:nil forClientWithIdentifier:identifier];
            return;
        }
        
        destPath = tmpPath;
    }
    
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:destPath];
    
    if( !dictionary ) {
        [self setError:[TICDSError errorWithCode:TICDSErrorCodeFileManagerError classAndMethod:__PRETTY_FUNCTION__]];
    }
    
    [self fetchedDeviceInfoDictionary:dictionary forClientWithIdentifier:identifier];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    NSString *path = [[error userInfo] valueForKey:@"path"];
    NSString *destinationPath = [[error userInfo] valueForKey:@"destinationPath"];
    NSInteger errorCode = error.code;
    
    if (errorCode == 503) { // Potentially bogus rate-limiting error code. Current advice from Dropbox is to retry immediately. --M.Fey, 2012-12-19
        TICDSLog(TICDSLogVerbosityErrorsOnly, @"Encountered an error 503, retrying immediately. %@", path);
        [client loadFile:path intoPath:destinationPath];
        return;
    }
    

    [self setError:[TICDSError errorWithCode:TICDSErrorCodeDropboxSDKRestClientError underlyingError:error classAndMethod:__PRETTY_FUNCTION__]];
    
    NSString *clientIdentifier = [[path stringByDeletingLastPathComponent] lastPathComponent];
    [self fetchedDeviceInfoDictionary:nil forClientWithIdentifier:clientIdentifier];
}

#pragma mark - Initialization and Deallocation
- (void)dealloc
{
    [_restClient setDelegate:nil];

    _restClient = nil;
    _clientDevicesDirectoryPath = nil;
    _documentsDirectoryPath = nil;

}

#pragma mark - Lazy Accessors
- (DBRestClient *)restClient
{
    if( _restClient ) return _restClient;
    
    _restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
    [_restClient setDelegate:self];
    
    return _restClient;
}

#pragma mark - Properties
@synthesize clientDevicesDirectoryPath = _clientDevicesDirectoryPath;
@synthesize documentsDirectoryPath = _documentsDirectoryPath;

@end

#endif