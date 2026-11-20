#include "ASTSwiftUIVisibility.h"

typedef void * __attribute__((swiftcall)) (*ASTResponderGetter)(
    const void *, const void *, const void * __attribute__((swift_context)));

void *ASTCopySwiftUIVisibilityResponder(const void *geometry, const void *getter, const void *metadata) {
    // Swift passes both the explicit metatype and the generic type metadata before swiftself.
    return ((ASTResponderGetter)getter)(metadata, metadata, geometry);
}
