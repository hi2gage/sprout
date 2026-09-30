#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C `@try/@catch` and returns any `NSException` it
/// raises, or `nil` on success.
///
/// Foundation APIs such as `Process` can raise Objective-C `NSException`s (for example when
/// the inherited working directory has been deleted) that Swift's `do`/`catch` cannot
/// intercept — an uncaught one aborts the whole process. Routing the call through this
/// shim lets Swift callers convert the exception into a recoverable `Error` instead.
NSException *_Nullable oec_runCatchingExceptions(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
