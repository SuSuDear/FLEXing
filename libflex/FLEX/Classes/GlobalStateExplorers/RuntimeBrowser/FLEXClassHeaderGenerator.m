//
//  FLEXClassHeaderGenerator.m
//  FLEX
//

#import "FLEXClassHeaderGenerator.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXPropertyAttributes.h"
#import <objc/runtime.h>

@implementation FLEXClassHeaderGenerator

+ (NSString *)headerForClass:(Class)cls {
    if (!cls) {
        return @"// Unable to generate header: class is nil\n";
    }

    NSMutableString *header = [NSMutableString string];
    NSString *className = NSStringFromClass(cls);
    NSString *superName = NSStringFromClass(class_getSuperclass(cls));
    NSString *imageName = [self imageNameForClass:cls];

    [header appendString:@"//\n"];
    [header appendString:@"// Dumped by FLEXing\n"];
    [header appendFormat:@"// Bundle: %@\n", NSBundle.mainBundle.bundleIdentifier ?: @"Unknown"];
    if (imageName.length) {
        [header appendFormat:@"// Image: %@\n", imageName];
    }
    [header appendString:@"//\n\n"];

    [header appendString:@"#import <Foundation/Foundation.h>\n"];
    [header appendString:@"#import <UIKit/UIKit.h>\n\n"];

    NSArray<NSString *> *protocols = [self protocolNamesForClass:cls];
    NSString *protocolString = protocols.count ? [NSString stringWithFormat:@" <%@>", [protocols componentsJoinedByString:@", "]] : @"";
    [header appendFormat:@"@interface %@ : %@%@\n", className, superName ?: @"NSObject", protocolString];

    NSArray<NSString *> *ivars = [self ivarDeclarationsForClass:cls];
    if (ivars.count) {
        [header appendString:@"{\n"];
        for (NSString *ivar in ivars) {
            [header appendFormat:@"    %@\n", ivar];
        }
        [header appendString:@"}\n"];
    }

    NSArray<NSString *> *properties = [self propertyDeclarationsForClass:cls];
    if (properties.count) {
        [header appendString:@"\n#pragma mark - Properties\n\n"];
        for (NSString *property in properties) {
            [header appendFormat:@"%@\n", property];
        }
    }

    NSArray<NSString *> *classMethods = [self methodDeclarationsForClass:object_getClass(cls) instance:NO];
    if (classMethods.count) {
        [header appendString:@"\n#pragma mark - Class Methods\n\n"];
        for (NSString *method in classMethods) {
            [header appendFormat:@"%@\n", method];
        }
    }

    NSArray<NSString *> *instanceMethods = [self methodDeclarationsForClass:cls instance:YES];
    if (instanceMethods.count) {
        [header appendString:@"\n#pragma mark - Instance Methods\n\n"];
        for (NSString *method in instanceMethods) {
            [header appendFormat:@"%@\n", method];
        }
    }

    [header appendString:@"\n@end\n"];
    return header.copy;
}

+ (NSString *)imageNameForClass:(Class)cls {
    const char *imageName = class_getImageName(cls);
    return imageName ? [@(imageName) lastPathComponent] : nil;
}

+ (NSArray<NSString *> *)protocolNamesForClass:(Class)cls {
    unsigned int count = 0;
    Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *name = protocol_getName(protocols[i]);
        if (name) {
            [names addObject:@(name)];
        }
    }
    free(protocols);
    return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (NSArray<NSString *> *)ivarDeclarationsForClass:(Class)cls {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSMutableArray<NSString *> *declarations = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *name = ivar_getName(ivars[i]);
        const char *type = ivar_getTypeEncoding(ivars[i]);
        NSString *readableType = [FLEXRuntimeUtility readableTypeForEncoding:type ? @(type) : nil];
        NSString *ivarName = name ? @(name) : @"unknown";
        [declarations addObject:[NSString stringWithFormat:@"%@;", [FLEXRuntimeUtility appendName:ivarName toType:readableType]]];
    }
    free(ivars);
    return declarations;
}

+ (NSArray<NSString *> *)propertyDeclarationsForClass:(Class)cls {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableArray<NSString *> *declarations = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(properties[i]);
        if (!name) {
            continue;
        }

        FLEXPropertyAttributes *attributes = [FLEXPropertyAttributes attributesForProperty:properties[i]];
        NSString *type = [FLEXRuntimeUtility readableTypeForEncoding:attributes.typeEncoding];
        NSString *typedName = [FLEXRuntimeUtility appendName:@(name) toType:type];
        [declarations addObject:[NSString stringWithFormat:@"@property (%@) %@;", attributes.fullDeclaration, typedName]];
    }
    free(properties);
    return declarations;
}

+ (NSArray<NSString *> *)methodDeclarationsForClass:(Class)cls instance:(BOOL)instance {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *declarations = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        [declarations addObject:[self declarationForMethod:methods[i] instance:instance]];
    }
    free(methods);
    return [declarations sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (NSString *)declarationForMethod:(Method)method instance:(BOOL)instance {
    NSString *selectorName = NSStringFromSelector(method_getName(method));
    char *returnType = method_copyReturnType(method);
    NSString *readableReturnType = [FLEXRuntimeUtility readableTypeForEncoding:returnType ? @(returnType) : nil];
    free(returnType);

    NSArray<NSString *> *selectorPieces = [selectorName componentsSeparatedByString:@":"];
    unsigned int argumentCount = method_getNumberOfArguments(method);
    unsigned int explicitArgumentCount = argumentCount > 2 ? argumentCount - 2 : 0;
    NSString *prefix = instance ? @"-" : @"+";

    if (explicitArgumentCount == 0) {
        return [NSString stringWithFormat:@"%@ (%@)%@;", prefix, readableReturnType, selectorName];
    }

    NSMutableString *declaration = [NSMutableString stringWithFormat:@"%@ (%@)", prefix, readableReturnType];
    for (unsigned int i = 0; i < explicitArgumentCount; i++) {
        NSString *piece = i < selectorPieces.count ? selectorPieces[i] : @"arg";
        char *argumentType = method_copyArgumentType(method, i + 2);
        NSString *readableArgumentType = [FLEXRuntimeUtility readableTypeForEncoding:argumentType ? @(argumentType) : nil];
        free(argumentType);

        if (i == 0) {
            [declaration appendFormat:@"%@:(%@)arg%u", piece, readableArgumentType, i];
        } else {
            [declaration appendFormat:@" %@:(%@)arg%u", piece.length ? piece : @"arg", readableArgumentType, i];
        }
    }
    [declaration appendString:@";"];
    return declaration.copy;
}

@end
