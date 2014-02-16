module astdump;

import parser;
import std.stdio : writefln, writeln;
import std.file : readText;
import std.conv : text, dtext, to;
import std.array : replicate;


string codeToAstString(string code) {
	string result;

	string textRange(const TextRange t) {
		assert(t !is null);
		return format("%d..%d  %d:%d..%d:%d", t.begin.index, t.end.index,
			t.begin.line, t.begin.column, t.end.line, t.end.column);
	}


	int level = 0;

	string indent() {
		return replicate("  ", level);
	}

	void field(T)(string key, T value) {
		result ~= format("%s%s: '%s'\n", indent(), key, to!string(value));
	}

	class ASTDumpVisitor : Visitor {

		void start(TextRange d) {
			assert(d !is null);
			result ~= format("%s%s '%s':\n", indent(), d.classinfo.name, d.textInRange);
			level++;
		}

		void stop() {
			level--;
		}

		override public void visit(ModuleName element) {
			start(element); scope(exit) { element.accept(this); stop(); }

			field("name", element.name);
			field("parts", element.parts);
		}

		override public void visit(ModuleDeclaration element) {
			start(element); scope(exit) { element.accept(this); stop(); }
		}

		override public void visit(ImportDeclaration element) {
			start(element); scope(exit) { element.accept(this); stop(); }

			field("isStatic", element.isStatic);
		}

		override public void visit(Import element) {
			start(element); scope(exit) { element.accept(this); stop(); }

			field("aliasName", element.aliasName);
		}

		override public void visit(ImportSymbol element) {
			start(element); scope(exit) { element.accept(this); stop(); }

			field("aliasName", element.aliasName);
			field("name", element.name);
		}

		alias Visitor.visit visit;
	}


	Module m = parse(dtext(code));
	foreach (error; m.errors) {
		result ~= format("'%s': error: %s\n", error.textInRange, error.message);
		level++;
		field("textRange", textRange(error));
		level--;
	}
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; m.declarations) {
		dumper.visit(declaration);
	}

	return result;
}
