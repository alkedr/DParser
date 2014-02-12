module ast;

import std.array : join;
import std.algorithm : map;
import std.string : format;
import std.traits : isArray, isBasicType;


template generateAbstractVisitor(classNames...) {
	immutable string generateAbstractVisitor =
		"public void visit(TextRange e) {" ~
			[classNames].map!(s => format("if (cast(%1$s)e) visit(cast(%1$s)e);", s)).join("else ") ~
		"}" ~
		[classNames].map!(s => format("public void visit(%s e) { e.accept(this); }", s)).join();
}

abstract class Visitor {
	mixin(generateAbstractVisitor!(
		"ModuleDeclaration",
		"ModuleName",
		"Import",
		"ImportDeclaration",
		"ImportSymbol",
	));
};

void accept(T)(T element, Visitor visitor) {
	foreach (field; (cast(T)element).tupleof) {
		static if (isArray!(typeof(field))) {
			foreach (arrayItem; field) {
				if (arrayItem !is null) visitor.visit(arrayItem);
			}
		} else static if (!isBasicType!(typeof(field))) {
			if (field !is null) visitor.visit(field);
		}
	}
}


struct Cursor {
	uint index;
	uint line = 1;
	uint column = 1;
}


class TextRange {
	Cursor begin;
	Cursor end;
	const(dchar)[] wholeText;

	this(const(dchar)[] wholeText = null, Cursor begin = Cursor(), Cursor end = Cursor()) {
		this.wholeText = wholeText;
		this.begin = begin;
		this.end = end;
	}

	@property const(dchar)[] textInRange() const {
		assert(wholeText !is null);
		return wholeText[begin.index .. end.index];
	}
}


class Element : TextRange {
}


class Declaration : Element {
}


class Identifier : Element {
	alias textInRange this;
}


class ModuleName : Element {
	Identifier[] parts;

	@property const(dchar)[] name() {
		return parts.map!(x => x.textInRange).join("."d);
	}

	alias name this;
}

class ModuleDeclaration : Declaration {
	ModuleName name;
}

class ImportSymbol : Element {
	Identifier aliasName;
	Identifier name;
}

class Import : Element {
	Identifier aliasName;
	ModuleName moduleName;
	ImportSymbol[] symbols;
}

class ImportDeclaration : Declaration {
	bool isStatic;
	Import[] imports;
}
