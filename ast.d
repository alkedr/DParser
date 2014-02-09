module ast;

import std.array : join;


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


class TextRange {
	TextPosition begin;
	TextPosition end;
	const(dchar)[] text;
}


class Element {
	public void accept(Visitor visitor) {}
}


class Declaration : Element {
	TextRange textRange;
}

class ModuleDeclaration : Declaration {
	const(dchar)[][] names;

	@property const(dchar)[] name() { return join(names, "."d); }
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

