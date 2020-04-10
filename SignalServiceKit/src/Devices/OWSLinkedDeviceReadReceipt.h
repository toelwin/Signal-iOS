//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "BaseModel.h"

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;

@interface OWSLinkedDeviceReadReceipt : BaseModel

@property (nonatomic, readonly) SignalServiceAddress *senderAddress;
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t readTimestamp;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;
- (instancetype)initWithGrdbId:(int64_t)grdbId uniqueId:(NSString *)uniqueId NS_UNAVAILABLE;

- (instancetype)initWithSenderAddress:(SignalServiceAddress *)address
                   messageIdTimestamp:(uint64_t)messageIdtimestamp
                        readTimestamp:(uint64_t)readTimestamp NS_DESIGNATED_INITIALIZER;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
              messageIdTimestamp:(uint64_t)messageIdTimestamp
                   readTimestamp:(uint64_t)readTimestamp
               senderPhoneNumber:(nullable NSString *)senderPhoneNumber
                      senderUUID:(nullable NSString *)senderUUID
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:messageIdTimestamp:readTimestamp:senderPhoneNumber:senderUUID:));

// clang-format on

// --- CODE GENERATION MARKER

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithAddress:(SignalServiceAddress *)address
                                                             messageIdTimestamp:(uint64_t)messageIdTimestamp
                                                                    transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
