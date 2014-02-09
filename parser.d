module parser;

public import ast;

import std.ascii;
import std.string : format;
import std.conv;
import std.range;
import std.array;
import std.stdio;
import std.algorithm;


public class ParseError {
	string text;
}


public class Module {
	Declaration[] declarations = [];
	ParseError[] errors = [];
}



public Module parse(const(dchar)[] text) {
	text ~= 0;

	auto result = new Module;

	size_t position = 0;
	size_t line = 1;
	size_t column = 1;

	bool isEOF() { return position >= text.length-1; }

	dchar currentChar() { return text[position]; }
	dchar advance() { return isEOF() ? 0 : text[++position]; }
	dchar getCurrentCharAndAdvance() { return isEOF() ? 0 : text[position++]; }


	TextRange[] textRangeStack;

	void initTextRange(ref TextRange textRange) {
		textRange.firstCharIndex = position;
		textRange.line = line;
		textRange.column = column;
	}

	void startTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length), __FUNCTION__, " ", position);
		auto textRange = new TextRange;
		initTextRange(textRange);
		textRangeStack ~= textRange;
	}

	ref TextRange currentTextRange() {
		assert(textRangeStack.length > 0);
		return textRangeStack[$-1];
	}

	void restartTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", position);
		initTextRange(currentTextRange());
	}

	TextRange endTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", position);
		TextRange result = currentTextRange();
		textRangeStack = textRangeStack[0..$-1];
		result.text = text[result.firstCharIndex..position];
		return result;
	}



	immutable auto identifierFirstChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"d;
	immutable auto identifierChars = identifierFirstChars ~ "0123456789"d;
	immutable auto whitespaceChars = "\u0020\u0009\u000B\u000C"d;
	immutable auto lineBreakChars = "\u000D\u000A\u2028\u2029"d;



	struct SuffixTree {
		SuffixTree[dchar] _impl;
		string action;

		//invariant() {
		//	assert((action != "") || (_impl.length > 0));
		//}

		SuffixTree oneOfChars(const dchar[] chars, string action) {
			return add([chars], action);
		}

		SuffixTree oneOfChars(dchar c, string action) {
			return oneOfChars([c], action);
		}

		SuffixTree charSequence(const dchar[] chars, string action) {
			dchar[][] sequence;
			foreach (c; chars) sequence ~= [c];
			return add(sequence, action);
		}

		SuffixTree keyword(const dchar[] chars, string actionOnMatch, string actionOnMismatch) {
			return charSequence(chars,
				"if(isIdentifierChar(currentChar())){" ~
					actionOnMismatch ~
				"}else{" ~
					actionOnMatch ~
				"}"
			);
		}

		SuffixTree noMatch(string action) {
			assert(this.action is null);
			this.action = action;
			return this;
		}

		SuffixTree skipWhitespace() {
			return oneOfChars(whitespaceChars, "restartTextRange();");
		}

		SuffixTree ignoreWhitespace() {
			return oneOfChars(whitespaceChars, " ");
		}

		SuffixTree skipLineBreaks() {
			return oneOfChars(lineBreakChars, "restartTextRange();");
		}

		SuffixTree ignoreLineBreaks() {
			return oneOfChars(lineBreakChars, " ");
		}

		SuffixTree handleComments() {
			return charSequence("//", "finishParsingLineComment();")
			      .charSequence("/*", "finishParsingBlockComment();")
			      .charSequence("/+", "finishParsingNestingBlockComment();");
		}


		string generate() const {
			return "while(!isEOF()){" ~ code ~ "}";
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
				assert(this.action is null);
				this.action = action;
			}
			return this;
		}

		private string code() const {
			if (_impl.length == 0) return action;
			string result = "switch(getCurrentCharAndAdvance()){";

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
				result ~= "{" ~ generatedCode ~ "}break;";
			}

			if (action !is null) {
				result ~= format(`default:{%s}break;}`, action);
			} else {
				result ~= `default:}`;
			}

			return result;
		}
	}

	template generateParser(rulesTuple...) {
		immutable string generateParser = rulesTuple[0].generate();
	}


	bool isIdentifierChar(dchar c) {
		return isAlphaNum(c) || (c == '_');
	}

	bool isWhitespaceChar(dchar c) {
		return (c == '\u0020') || (c == '\u0009') || (c == '\u000B') || (c == '\u000C');
	}

	void error(string text) {
		auto error = new ParseError;
		error.text = text;
		result.errors ~= error;
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

	void finishParsingIdentifier()
	in {
		assert(currentTextRange.firstCharIndex < position);
		//assert(text[currentTextRange.firstCharIndex]);
		//assert(identifierFirstChars.contains(currentTextRange.text[0]));
	} out {
		assert(!isIdentifierChar(text[position]));
	} body {
		while (isIdentifierChar(advance())) {}
	}

	void finishParsingModuleDeclaration()
	in {
		//assert(moduleKeywordTextRange.text == "module");
		//assert(position == moduleKeywordTextRange.firstCharIndex + moduleKeywordTextRange.text.length);
	}
	body {
		auto d = new ModuleDeclaration;

		void parsedModuleName(TextRange textRange) {
			if (d.name.length > 0) d.name ~= '.';
			d.name ~= textRange.text;
		}

		void finish() {
			d.textRange = endTextRange();
			result.declarations ~= d;
		}

		void fail() {
			finish();
			error("missing semicolon");
		}

		void onIdentifier() {
			finishParsingIdentifier();
			parsedModuleName(endTextRange());
			startTextRange();
		}

		startTextRange();
		mixin(generateParser!(SuffixTree().skipWhitespace().skipLineBreaks().handleComments()
			.oneOfChars(identifierFirstChars, "onIdentifier();")
			.oneOfChars(['.'], "restartTextRange();")
			.oneOfChars([';'], "endTextRange(); return finish();")
			.noMatch("endTextRange(); return fail();")
		));
		endTextRange();
		fail();
	}

	void finishParsingImportDeclaration() {
		void parseImportList(TextRange textRange) {
			assert(0);
		}

		startTextRange();
		mixin(generateParser!(SuffixTree().ignoreWhitespace().ignoreLineBreaks().handleComments()
			.oneOfChars(identifierChars, "return parseImportList(endTextRange());")
		));
	}

	void parseDeclaration() {
		startTextRange();
		mixin(generateParser!(SuffixTree().skipWhitespace().skipLineBreaks().handleComments()
			.keyword("module", "return finishParsingModuleDeclaration();", "return finishParsingIdentifier();")
			.keyword("import", "return finishParsingImportDeclaration();", "return finishParsingIdentifier();")
		));
	}

	//writeln(SuffixTree()
	//		.oneOfChars(identifierChars, " ")
	//		.noMatch("return;")
	//	.generate());


	while (!isEOF()) {
		parseDeclaration();
	}

	return result;
}

unittest {
	parse("");
}
