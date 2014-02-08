module parser;

public import ast;

import std.ascii;
import std.string : format;
import std.conv : dtext;
import std.stdio;


private struct SuffixTree {
	private SuffixTree[immutable(dchar)[]] _impl;
	string action = "";

	alias _impl this;

	SuffixTree oneOfChars(const dchar[] chars, string action) {
		return add([chars], action);
	}

	private const(dchar[][]) splitIntoOneCharStrings(const dchar[] chars) {
		dchar[][] result;
		foreach (c; chars) result ~= [c];
		return result;
	}

	SuffixTree charSequence(const dchar[] chars, string action) {
		return add(splitIntoOneCharStrings(chars), action);
	}

	SuffixTree keyword(const dchar[] chars, string actionOnMatch, string actionOnMismatch) {
		return add(splitIntoOneCharStrings(chars), actionOnMatch)
		      .add(splitIntoOneCharStrings(chars) ~ [identifierChars], actionOnMismatch);
	}

	/*SuffixTree keywords(const dchar[][] strings, string action) {
		const(dchar[])[][] result;
		foreach (s; strings) result ~= [splitIntoOneCharStrings(s)];
		return result;
	}*/

	string code() {
		if (_impl.length == 0) return action;
		string result = "switch(currentChar()){";
		foreach (keys, subtree; _impl) {
			foreach (key; keys) result ~= format(`case'\U%08X':`, key);
			result ~= "{advance();" ~ subtree.code() ~ "}break;";
		}
		return result ~ format(`default:{%s}break;}`, action);
	}

//TODO: invariant

	//key - array of possible values for chars
	//key[i] - array of possible values for char #i
	//key[i][j] - one of possible values for char #i
	private SuffixTree add(const(dchar[][]) key, string action) {
		if (key.length > 0) {
			foreach (c; key[0]) {
				if ([c] !in _impl) {
					_impl[[c]] = SuffixTree();
				}
				_impl[[c]].add(key[1..$], action);
			}
		} else {
			assert(this.action == "");
			this.action = action;
		}
		return this;
	}

	public void mergeKeysWithEqualValues() {
		/*foreach (c, subtree; _impl) {
			subtree.mergeKeysWithEqualValues();
		}

		SuffixTree[immutable(dchar)[]] newImpl;
		while (_impl.length > 0) {
			SuffixTree subtree = _impl.values[0];
			immutable(dchar)[] keys;
			foreach (key, value; _impl) {
				if (value == subtree) keys ~= key;
			}
			foreach (key; keys) {
				_impl.remove([key]);
			}
			newImpl[keys] = subtree;
		}

		_impl = newImpl;*/
	}

	const bool opEquals(ref const SuffixTree other) const pure @safe {
		if (action != other.action) return false;
		foreach (key, value; _impl) {
			if (key !in other._impl) return false;
			if (other._impl[key] != value) return false;
		}
		foreach (key, value; other._impl) {
			if (key !in _impl) return false;
			if (_impl[key] != value) return false;
		}

		return true;
	}
}

private string generateParserCode(SuffixTree tree) {
	return "size_t firstCharIndex=position+1;while(!isEOF()){"~tree.code~"}";
}

private template generateParser(rulesTuple...) {
	immutable string generateParser = generateParserCode(rulesTuple);
}



private immutable dstring identifierChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
private immutable dstring whitespaceChars = "\u0020\u0009\u000B\u000C";
private immutable dstring lineBreakChars = "\u000D\u000A\u2028\u2029";



private SuffixTree suffixTreeThatKnowsAboutCommentsAndWhitespace() {
	return SuffixTree()
		.oneOfChars(whitespaceChars, q{ firstCharIndex = position; continue; })
		.oneOfChars(lineBreakChars, q{ firstCharIndex = position; continue; })
		.charSequence("//", q{ finishParsingLineComment(); })
		.charSequence("/*", q{ finishParsingBlockComment(); })
		.charSequence("/+", q{ finishParsingNestingBlockComment(); });
}



public Declaration[] parse(const(dchar)[] text) {
	text ~= 0;

	Declaration[] result;

	size_t position = 0;
	size_t line = 1;
	size_t column = 1;

	bool isEOF() { return position >= text.length-1; }

	dchar currentChar() { return text[position]; }
	dchar advance() { return isEOF() ? 0 : text[++position]; }

	bool isIdentifierChar(dchar c) {
		return isAlphaNum(c) || (c == '_');
	}

	bool isWhitespaceChar(dchar c) {
		return (c == '\u0020') || (c == '\u0009') || (c == '\u000B') || (c == '\u000C');
	}

	void error(string text) {
		//writeln("Error: ", text);
	}

	void finishParsingIdentifier() {
		writeln(text[0..position]);
		assert(0);
	}

	void skipWhitespace() {
		while (isWhitespaceChar(currentChar())) {
			advance();
		}
	}

	void expectSemicolon() {
		skipWhitespace();
		(currentChar() == ';') ? advance() : error("missing semicolon");
	}

	Declaration finishParsingLineComment() {
		assert(0);
	}
	Declaration finishParsingBlockComment() {
		assert(0);
	}
	Declaration finishParsingNestingBlockComment() {
		assert(0);
	}

	void parseModuleName() {
		// TODO: parseIdentifier, expect . or ;, ...
		size_t moduleNameBegin = position-1;
		while (isIdentifierChar(currentChar()) || (currentChar() == '.')) {
			advance();
		}
		auto d = new ModuleDeclaration;
		d.name = text[moduleNameBegin..position];
		result ~= d;
		expectSemicolon();
	}

	void parseImportList() {
		assert(0);
	}

	void finishParsingModuleDeclaration() {
		if (isIdentifierChar(currentChar())) {
			finishParsingIdentifier();
		} else {
			mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
				.oneOfChars(identifierChars, q{ parseModuleName(); return; })
			));
		}
	}

	void finishParsingImportDeclaration() {
		if (isIdentifierChar(currentChar())) {
			finishParsingIdentifier();
		} else {
			mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
				.oneOfChars(identifierChars, q{ parseImportList(); return; })
			));
		}
	}

	//writeln(
	//	generateParserCode(SuffixTree()
	//		.oneOfChars(whitespaceChars, q{ firstCharIndex = position; continue; })
	//		.oneOfChars(lineBreakChars, q{ firstCharIndex = position; continue; })
	//		.charSequence("//", q{ finishParsingLineComment(); })
	//		.charSequence("/*", q{ finishParsingBlockComment(); })
	//		.charSequence("/+", q{ finishParsingNestingBlockComment(); })
	//		.oneOfChars(identifierChars, q{ parseModuleName(); return; })
	//	)
	//);

	mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
		.keyword("module", q{ finishParsingModuleDeclaration(); }, q{})
		.keyword("import", q{ finishParsingImportDeclaration(); }, q{})
	));

	return result;
}


unittest {
	writeln("Error {");
	Declaration[] decls = parse("module abc.def.ghi");
	assert(decls.length == 1);
	{
		ModuleDeclaration d = cast(ModuleDeclaration)decls[0];
		assert(d !is null);
		writeln(d.name);
		assert(d.name == "abc.def.ghi");
	}
	writeln("}");
}
