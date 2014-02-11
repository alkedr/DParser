module ast;

import std.array : join;
import std.algorithm : map;


abstract class Visitor {
	public void visit(Element element) {
		if (cast(ModuleDeclaration)element) visit(cast(ModuleDeclaration)element);
		else if (cast(ModuleName)element) visit(cast(ModuleName) element);
		else if (cast(Import)element) visit(cast(Import) element);
		else if (cast(ImportDeclaration)element) visit(cast(ImportDeclaration) element);
	}

	public void visit(ModuleDeclaration element) { element.accept(this); }
	public void visit(ImportDeclaration element) { element.accept(this); }
	public void visit(Import element) { element.accept(this); }
	public void visit(ModuleName element) { element.accept(this); }
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
	TextRange textRange;

	public void accept(Visitor visitor) {}
}


class Declaration : Element {
}


class Identifier : Element {
	alias textRange this;
}


class ModuleName : Element {
	Identifier[] parts;

	@property const(dchar)[] name() {
		return parts.map!(x => x.textRange.textInRange).join("."d);
	}

	alias name this;
}



class ModuleDeclaration : Declaration {
	ModuleName name;

	override public void accept(Visitor visitor) {
		visitor.visit(name);
	}
}

class Import : Declaration {
	Identifier aliasName;
	ModuleName moduleName;
	Identifier[] importBind;
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

