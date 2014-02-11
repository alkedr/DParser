module astdump;

import parser;
import std.stdio : writefln, writeln;
import std.file : readText;
import std.conv : text, dtext, to;
import std.array : replicate;


string textRange(TextRange t) {
	return format("%d..%d  %d:%d..%d:%d", t.begin.index, t.end.index,
		t.begin.line, t.begin.column, t.end.line, t.end.column);
}


int level = 0;

string indent() {
	return replicate("  ", level);
}

void field(T)(string key, T value) {
	writefln(`%s%s: '%s'`, indent(), key, to!string(value));
}

class ASTDumpVisitor : Visitor {

	void declaration(Declaration d) {
		assert(d !is null);
		writefln(`%s%s '%s':`, indent(), d.classinfo.name, d.textRange);
	}

	override public void visit(ModuleDeclaration element) {
		declaration(element);

		level++;
		field("textRange", textRange(element.textRange));
		field("name", element.name);
		field("packageNames", element.packageNames);
		element.accept(this);
		level--;
	}

	override public void visit(ImportDeclaration element) {
		declaration(element);

		level++;
		field("isStatic", element.isStatic);
		element.accept(this);
		level--;
	}

	alias Visitor.visit visit;
}


int main(string[] args) {
	if (args.length != 2) {
		writefln("Usage: %s <input.d>", args[0]);
		return 1;
	}

	Module m = parse(dtext(readText!(string)(args[1])));
	foreach (error; m.errors) {
		writeln("'", error.textRange , "': error: ", error.message);
		level++;
		field("textRange", textRange(error.textRange));
		level--;
	}
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; m.declarations) {
		dumper.visit(declaration);
	}

	return 0;
}
