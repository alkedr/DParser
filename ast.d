module ast;

import std.array : join;
import std.algorithm : map;
import std.string : format;


template generateAbstractVisitor(classNames...) {
	immutable string generateAbstractVisitor =
		"public void visit(Element element) {" ~
			[classNames].map!(s => format("if (cast(%1$s)element) visit(cast(%1$s)element);", s)).join("else ") ~
		"}" ~
		[classNames].map!(s => format("public void visit(%s element) { element.accept(this); }", s)).join();
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

	this() {}

	this(const(dchar)[] wholeText, TextPosition begin = TextPosition(), TextPosition end = TextPosition()) {
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
	public void accept(Visitor visitor) {}
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

	override public void accept(Visitor visitor) {
		visitor.visit(name);
	}
}

class ImportSymbol : Element {
	Identifier aliasName;
	Identifier name;
}

class Import : Element {
	Identifier aliasName;
	ModuleName moduleName;
	ImportSymbol[] symbols;

	override public void accept(Visitor visitor) {
		visitor.visit(moduleName);
		foreach (symbol; symbols) {
			visitor.visit(symbol);
		}
	}
}

class ImportDeclaration : Declaration {
	bool isStatic;
	Import[] imports;

	override public void accept(Visitor visitor) {
		foreach (i; imports) {
			visitor.visit(i);
		}
	}
}

