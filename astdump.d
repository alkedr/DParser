module astdump;

import parser;
import std.stdio : writefln, writeln;
import std.file : readText;
import std.conv : text, dtext, to;
import std.array : replicate;


class ASTDumpVisitor : Visitor {
	dstring result;

	private int indentLevel = 0;
	private dstring indent() { return replicate("  "d, indentLevel); }

	void dump(T)(T e) {
		result ~= indent ~ to!dstring(typeid(T)) ~ " '" ~ e.textInRange ~ "':\n";
		indentLevel++;
		foreach (fieldName; __traits(derivedMembers, T)) {
			static if (fieldName != "__ctor") {
				static if (is(typeof(__traits(getMember, e, fieldName)) == class)) {
					e.accept(this);
				} else {
					result ~= dtext(format("%s%s: '%s'\n"d, indent, dtext(fieldName), to!dstring(__traits(getMember, e, fieldName))));
				}
			}
		}
		indentLevel--;
	}

	alias Visitor.visit visit;

	override void visit(ModuleDeclaration e) { dump(e); }
	override void visit(ImportDeclaration e) { dump(e); }
	override void visit(ModuleName e) { dump(e); }
	override void visit(Import e) { dump(e); }
	override void visit(ImportSymbol e) { dump(e); }
}


dstring codeToAstString(dstring code) {
	dstring result;
	Module m = parse(code);
	foreach (e; m.errors) {
		result ~= dtext(format("'%s': error: %s\n  textRange: '%d..%d  %d:%d..%d:%d'\n",
			e.textInRange, e.message, e.begin.index, e.end.index,
			e.begin.line, e.begin.column, e.end.line, e.end.column));
	}
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; m.declarations) {
		dumper.visit(declaration);
	}
	return result ~ dumper.result;
}
