#import <MapKit/MapKit.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(CoreMLImageManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(modelFile, NSString);
RCT_EXPORT_VIEW_PROPERTY(isquant, BOOL)
RCT_EXPORT_VIEW_PROPERTY(inputDimension, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(onClassification, RCTBubblingEventBlock);
@end
