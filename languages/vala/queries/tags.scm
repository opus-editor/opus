; Written for Opus

(namespace_declaration (symbol) @name) @definition.module

(class_declaration (unqualified_type (symbol) @name)) @definition.class
(interface_declaration (unqualified_type (symbol) @name)) @definition.interface
(struct_declaration (unqualified_type (symbol) @name)) @definition.struct

(enum_declaration (symbol) @name) @definition.enum
(errordomain_declaration (symbol) @name) @definition.enum

(delegate_declaration (symbol) @name) @definition.delegate

(method_declaration (symbol) @name) @definition.method
(creation_method_declaration (symbol) @name) @definition.constructor

(property_declaration (symbol) @name) @definition.property
(signal_declaration (symbol) @name) @definition.signal

(constant_declaration (identifier) @name) @definition.constant
