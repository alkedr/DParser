module ast;

import std.array : join;
import std.algorithm : map;


abstract class Visitor {
	public void visit(Element element) {
		if (cast(ModuleDeclaration)element) visit(cast(ModuleDeclaration)element);
		else if (cast(ImportDeclaration)element) visit(cast(ImportDeclaration) element);
	}

	public void visit(ModuleDeclaration element) { element.accept(this); }
	public void visit(ImportDeclaration element) { element.accept(this); }
	public void visit(Import element) { element.accept(this); }
}



struct TextPosition {
	uint index;
	uint line = 1;
	uint column = 1;
}


struct TextRange {
	TextPosition begin;
	TextPosition end;
	private const(dchar)[] wholeText;

	this(const(dchar)[] wholeText, TextPosition begin = TextPosition(), TextPosition end = TextPosition()) {
		this.wholeText = wholeText;
		this.begin = begin;
		this.end = end;
	}

	@property const(dchar)[] textInRange() const {
		assert(wholeText !is null);
		return wholeText[begin.index .. end.index];
	}

	alias textInRange this;
}


class Element {
	public void accept(Visitor visitor) {}
}


class Declaration : Element {
	TextRange textRange;
}

class ModuleDeclaration : Declaration {
	TextRange[] packageNames;

	@property const(dchar)[] name() { return packageNames.map!(x => x.textInRange).join("."d); }
}

class Import : Declaration {
	const(dchar)[] aliasName;
	const(dchar)[] moduleName;
	const(dchar)[][] importBind;
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

