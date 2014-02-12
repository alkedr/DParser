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


struct TextPosition {
	uint index;
	uint line = 1;
	uint column = 1;
}


class TextRange {
	TextPosition begin;
	TextPosition end;
	const(dchar)[] wholeText;

	this(const(dchar)[] wholeText = null, TextPosition begin = TextPosition(), TextPosition end = TextPosition()) {
		this.wholeText = wholeText;
		this.begin = begin;
		this.end = end;
	}

	@property const(dchar)[] textInRange() const {
		assert(wholeText !is null);
		return wholeText[begin.index .. end.index];
	}
}


class Element(T) : TextRange {
	public final void accept(Visitor visitor) {
		foreach (field; (cast(T)this).tupleof) {
			static if (isArray!(typeof(field))) {
				foreach (arrayItem; field) {
					if (arrayItem !is null) visitor.visit(arrayItem);
				}
			} else static if (!isBasicType!(typeof(field))) {
				if (field !is null) visitor.visit(field);
			}
		}
	}
}


class Declaration : Element!(Declaration) {
}


class Identifier : Element!(Identifier) {
	alias textInRange this;
}


class ModuleName : Element!(ModuleName) {
	Identifier[] parts;

	@property const(dchar)[] name() {
		return parts.map!(x => x.textInRange).join("."d);
	}

	alias name this;
}



class ModuleDeclaration : Element!(ModuleDeclaration) {
	ModuleName name;
}

class ImportSymbol : Element!(ImportSymbol) {
	Identifier aliasName;
	Identifier name;
}

class Import : Element!(Import) {
	Identifier aliasName;
	ModuleName moduleName;
	ImportSymbol[] symbols;
}

class ImportDeclaration : Element!(ImportDeclaration) {
	bool isStatic;
	Import[] imports;
}
