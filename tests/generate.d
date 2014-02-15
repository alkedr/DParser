module generate;

import parser;
import std.stdio : File, writefln, writeln;
import std.file : remove;
import std.string : format;
import std.conv : to, dtext;
import std.array : replicate;
import std.process : executeShell;
import std.exception : assumeUnique;



void combineImpl(implArgs...)(const string arg, void delegate(const string code, const string ast) f, string code, string ast) {
	combine!(implArgs[1..$])(f, code ~ arg, ast);
}

void combineImpl(implArgs...)(const(string[]) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	foreach (newCode; arg) combine!(implArgs[1..$])(f, code ~ newCode, ast);
}

void combineImpl(implArgs...)(const(string[string]) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	foreach (newCode, newAst; arg) combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
}

void combineImpl(implArgs...)(void function(void delegate(const string code, const string ast) f) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	arg((const string newCode, const string newAst) {
		combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
	});
}

void combineImpl(implArgs...)(void delegate(void delegate(const string code, const string ast) f) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	arg((const string newCode, const string newAst) {
		combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
	});
}

void combine(args...)(void delegate(const string code, const string ast) f, string code = "", string ast = "") {
	static if (args.length == 0) f(code, ast); else combineImpl!(args)(args[0], f, code, ast);
}

int level = 0;
string indent(int l = level) {
	return replicate("  ", l);
}

void combineNode(args...)(void delegate(const string code, const string ast) f, string code = "", string ast = "") {
	int l = level++;
	combine!(args[1..$])(
		(const string newCode, const string newAst) {
			f(newCode, format("%sast.%s '%s':\n", indent(l), args[0], newCode) ~ newAst);
		}
	);
	level--;
}

string field(string name, T)(const T value) {
	return format("%s%s: '%s'\n", indent, name, to!string(value));
}


void main() {
	immutable auto whitespace = ["\u0020", "\u0009", "\u000B", "\u000C"].assumeUnique;
	immutable auto lineBreak = ["\u000D", "\u000A", "\u000D\u000A", "\u2028", "\u2029"].assumeUnique;
	immutable auto sep = whitespace ~ lineBreak;

	immutable auto opt(immutable string[] arg) { return arg ~ ""; }


	auto moduleName = (void delegate(const string code, const string ast) f) {
		combineNode!("ModuleName", "a", opt(sep), ".", opt(sep), "bcd", opt(sep), ".", opt(sep), "e")(
			(const string code, const string ast) {
				f(code, ast ~ field!"name"(["a", "bcd", "e"].join(".")) ~ field!"parts"(["a", "bcd", "e"]));
			}
		);
	};

	auto moduleDeclaration = (void delegate(const string code, const string ast) f) {
		combineNode!("ModuleDeclaration", "module", sep, moduleName, opt(sep), ";")(f);
	};


	int i;
	moduleDeclaration(
		(const string code, const string ast) {
			test(code, ast);
			i++;
		}
	);
	writeln(i);
}



void test(string code, string correctAst) {
	string actualAst;


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
		actualAst ~= format("%s%s: '%s'\n", indent(), key, to!string(value));
	}

	class ASTDumpVisitor : Visitor {

		void start(TextRange d) {
			assert(d !is null);
			actualAst ~= format("%s%s '%s':\n", indent(), d.classinfo.name, d.textInRange);
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
		actualAst ~= format("'%s': error: %s\n", error.textInRange, error.message);
		level++;
		field("textRange", textRange(error));
		level--;
	}
	auto dumper = new ASTDumpVisitor;
	foreach (declaration; m.declarations) {
		dumper.visit(declaration);
	}


	if (correctAst != actualAst) {
		writeln("'", code, "'");
		File("tmp.d",   "w").writeln(correctAst);
		File("tmp.ast", "w").writeln(actualAst);
		writeln(executeShell("git diff --no-index --color --unified=999999999 tmp.d tmp.ast | tail -n +6").output);
		remove("tmp.d");
		remove("tmp.ast");
	}

}
