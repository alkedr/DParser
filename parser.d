module parser;

public import ast;

import std.ascii;
import std.string : format;
import std.conv : dtext;
import std.stdio;
import std.range;
import std.array;
import std.algorithm;


private struct SuffixTree {
	SuffixTree[dchar] _impl;
	string action = "";

	//invariant() {
	//	assert((action != "") || (_impl.length > 0));
	//}

	SuffixTree oneOfChars(const dchar[] chars, string action) {
		return add([chars], action);
	}

	SuffixTree charSequence(const dchar[] chars, string action) {
		return add(splitIntoOneCharStrings(chars), action);
	}

	SuffixTree keyword(const dchar[] chars, string actionOnMatch, string actionOnMismatch) {
		return add(splitIntoOneCharStrings(chars), actionOnMatch)
		      .add(splitIntoOneCharStrings(chars) ~ [identifierChars], actionOnMismatch);
	}

	// TODO: token (variable length)
	SuffixTree token(const dchar[] chars, string action) {
		return oneOfChars(chars, /*SuffixTree().oneOfChars(chars, ) ~*/ action);
	}

	SuffixTree identifier(string action) {
		return token(identifierChars, action);
	}

	/*SuffixTree keywords(const dchar[][] strings, string action) {
		const(dchar[])[][] result;
		foreach (s; strings) result ~= [splitIntoOneCharStrings(s)];
		return result;
	}*/

	string generate() const {
		return "size_t firstCharIndex=position+1;while(!isEOF()){" ~ code ~ "}";
	}


	private static const(dchar[][]) splitIntoOneCharStrings(const dchar[] chars) pure @safe nothrow {
		dchar[][] result;
		foreach (c; chars) result ~= [c];
		return result;
	}

	//key - array of possible values for chars
	//key[i] - array of possible values for char #i
	//key[i][j] - one of possible values for char #i
	private SuffixTree add(const(dchar[][]) key, string action) {
		if (key.length > 0) {
			foreach (c; key[0]) {
				if (c !in _impl) _impl[c] = SuffixTree();
				_impl[c].add(key[1..$], action);
			}
		} else {
			assert(this.action == "");
			this.action = action ~ "(new TextRange(firstCharIndex, line, column, text[firstCharIndex..position]));";
		}
		return this;
	}

	public string code() const {
		if (_impl.length == 0) return action;
		string result = "switch(currentChar()){";

		dchar[][string] codeToCharsMap;
		foreach (key, value; _impl) {
			auto generatedCode = value.code;
			if (generatedCode in codeToCharsMap) {
				codeToCharsMap[generatedCode] ~= key;
			} else {
				codeToCharsMap[generatedCode] = [key];
			}
		}

		foreach (generatedCode, chars; codeToCharsMap) {
			foreach (c; chars) result ~= format(`case'\U%08X':`, c);
			result ~= "{advance();" ~ generatedCode ~ "}break;";
		}

		return result ~ format(`default:{%s}break;}`, action);
	}
}

private template generateParser(rulesTuple...) {
	immutable string generateParser = rulesTuple[0].generate();
}



private immutable auto identifierChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"d;
private immutable auto whitespaceChars = "\u0020\u0009\u000B\u000C"d;
private immutable auto lineBreakChars = "\u000D\u000A\u2028\u2029"d;



private SuffixTree suffixTreeThatKnowsAboutCommentsAndWhitespace() {
	return SuffixTree()
		.oneOfChars(whitespaceChars, q{ firstCharIndex = position; continue; })
		.oneOfChars(lineBreakChars, q{ firstCharIndex = position; continue; })
		.charSequence("//", "finishParsingLineComment")
		.charSequence("/*", "finishParsingBlockComment")
		.charSequence("/+", "finishParsingNestingBlockComment");
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

	void finishParsingIdentifier(TextRange textRange) {
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

	Declaration finishParsingLineComment(TextRange textRange) {
		assert(0);
	}
	Declaration finishParsingBlockComment(TextRange textRange) {
		assert(0);
	}
	Declaration finishParsingNestingBlockComment(TextRange textRange) {
		assert(0);
	}

	void finishParsingModuleDeclaration(TextRange moduleKeywordTextRange) {
		void parseModuleName(TextRange textRange) {
			// TODO: parseIdentifier, expect . or ;, ...
			size_t moduleNameBegin = position-1;
			while (isIdentifierChar(currentChar()) || (currentChar() == '.')) {
				advance();
			}
			auto d = new ModuleDeclaration;
			d.textRange = textRange;
			d.name = text[moduleNameBegin..position];
			result ~= d;
			expectSemicolon();
		}

		mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
			.oneOfChars(identifierChars, "return parseModuleName")
		));
	}

	void finishParsingImportDeclaration(TextRange importKeywordTextRange) {
		void parseImportList(TextRange textRange) {
			assert(0);
		}

		mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
			.oneOfChars(identifierChars, "return parseImportList")
		));
	}

	mixin(generateParser!(suffixTreeThatKnowsAboutCommentsAndWhitespace()
		.keyword("module", "finishParsingModuleDeclaration", "finishParsingIdentifier")
		.keyword("import", "finishParsingImportDeclaration", "finishParsingIdentifier")
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
