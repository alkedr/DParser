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

	void declaration(Declaration d) {
		writefln(`%s%s (%d..%d, %d:%d):`, indent(), d.classinfo.name,
			d.firstCharIndex, d.firstCharIndex+d.text.length, d.line, d.column);
	}

	void field(T)(string key, T value) {
		writefln(`%s%s: '%s'`, indent(), key, to!string(value));
	}

	override public void visit(ModuleDeclaration element) {
		declaration(element);

		level++;
		field("name", element.name);
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

	Declaration[] declarations = parse(dtext(readText!(string)(args[1])));
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; declarations) {
		dumper.visit(declaration);
	}

	return 0;
}
