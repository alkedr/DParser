module astdump;

import parser;
import std.stdio : writefln, writeln;
import std.file : readText;
import std.conv : text, dtext, to;
import std.array : replicate;


class ASTDumpVisitor : Visitor {
	int level = 0;

	string indent() {
		return replicate("  ", level);
	}

	void textRange(TextRange t) {
	}

	void declaration(Declaration d) {
		assert(d !is null);
		assert(d.textRange.text !is null);
		writefln(`%s%s (%d..%d, %d:%d..%d:%d):`, indent(), d.classinfo.name,
			d.textRange.begin.index, d.textRange.end.index,
			d.textRange.begin.line, d.textRange.begin.column,
			d.textRange.end.line, d.textRange.end.column);
	}

	void field(T)(string key, T value) {
		writefln(`%s%s: '%s'`, indent(), key, to!string(value));
	}

	override public void visit(ModuleDeclaration element) {
		declaration(element);

		level++;
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
		writeln("Error: ", error.text);
	}
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; m.declarations) {
		dumper.visit(declaration);
	}

	return 0;
}
