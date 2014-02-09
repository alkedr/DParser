module ast;


abstract class Visitor {
	public void visit(Element element) {
		if (cast(ModuleDeclaration)element) visit(cast(ModuleDeclaration)element);
		else if (cast(ImportDeclaration)element) visit(cast(ImportDeclaration) element);
	}

	public void visit(ModuleDeclaration element) { element.accept(this); }
	public void visit(ImportDeclaration element) { element.accept(this); }
	public void visit(Import element) { element.accept(this); }
}



class TextRange {
	size_t firstCharIndex;
	size_t line;
	size_t column;
	const(dchar)[] text;

	this() {}
}


class Element {
	public void accept(Visitor visitor) {}
}


class Declaration : Element {
	TextRange textRange;
}

class ModuleDeclaration : Declaration {
	const(dchar)[] name;
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

