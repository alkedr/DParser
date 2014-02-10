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
	string message;
	TextRange textRange;
}

public class Module {
	Declaration[] declarations = [];
	ParseError[] errors = [];
}


public Module parse(const(dchar)[] text) {
	text ~= 0;
	text ~= 0;

	auto result = new Module;

	TextPosition positionBeforeThat;
	TextPosition previousPosition;
	TextPosition position;

	bool isEOF() { return position.index >= text.length-1; }

	dchar currentChar() { return text[position.index]; }
	dchar previousChar() { return text[previousPosition.index]; }

	dchar advance() {
		if (isEOF()) return 0;

		positionBeforeThat = previousPosition;
		previousPosition = position;

		if (((currentChar == '\u000D') && (text[position.index+1] != '\u000A')) ||
		    (currentChar == '\u000A') || (currentChar == '\u2028') || (currentChar == '\u2028')) {
			position.line++;
			position.column = 1;
		} else {
			position.column++;
		}

		return text[++position.index];
	}

	dchar getCurrentCharAndAdvance() {
		auto result = currentChar();
		advance();
		return result;
	}

	void goToPreviousChar() {
		position = previousPosition;
		previousPosition = positionBeforeThat;
	}


	TextRange[] textRangeStack;

	// new range starts with current char
	void startTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length), __FUNCTION__, " ", position);
		TextRange textRange;
		textRange.begin = position;
		textRangeStack ~= textRange;
	}

	ref TextRange currentTextRange() {
		assert(textRangeStack.length > 0);
		return textRangeStack[$-1];
	}

	// range starts with current char
	void restartTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", position);
		currentTextRange().begin = position;
	}

	// range starts with previous char
	void restartTextRangeIncludingPreviousChar() {
		currentTextRange().begin = previousPosition;
	}

	// range ends with previous char
	TextRange endTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", position);
		TextRange result = currentTextRange();
		textRangeStack = textRangeStack[0..$-1];
		result.end = position;
		result.text = text[result.begin.index .. result.end.index];
		return result;
	}


	immutable auto digits = "0123456789"d;
	immutable auto identifierFirstChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"d;
	immutable auto identifierChars = identifierFirstChars ~ digits;
	immutable auto whitespaceChars = "\u0020\u0009\u000B\u000C"d;
	immutable auto lineBreakChars = "\u000D\u000A\u2028\u2029"d;



	struct ParserGenerator {
		ParserGenerator[dchar] rules;
		string action;
		string whilePrefix;

		this(string whileLabel = null) {
			this.whilePrefix = whileLabel ~ ":";
		}

		ParserGenerator oneOfChars(const dchar[] chars, string action) {
			return add([chars], action);
		}

		ParserGenerator oneOfChars(dchar c, string action) {
			return oneOfChars([c], action);
		}

		ParserGenerator charSequence(const dchar[] chars, string action) {
			dchar[][] sequence;
			foreach (c; chars) sequence ~= [c];
			return add(sequence, action);
		}

		ParserGenerator keyword(const dchar[] chars, string actionOnMatch, string actionOnMismatch) {
			return charSequence(chars,
				"if(isIdentifierChar(currentChar())){" ~
					actionOnMismatch ~
				"}else{" ~
					actionOnMatch ~
				"}"
			);
		}

		ParserGenerator identifier(string action) {
			return oneOfChars(identifierFirstChars, "startTextRange(); restartTextRangeIncludingPreviousChar(); while(isIdentifierChar(advance())){}" ~ action);
		}

		ParserGenerator identifierThatCanStartWithDigit(string action) {
			return oneOfChars(identifierChars, "startTextRange(); restartTextRangeIncludingPreviousChar(); while(isIdentifierChar(advance())){}" ~ action);
		}

		ParserGenerator noMatch(string action) {
			assert(this.action is null);
			this.action = action;
			return this;
		}

		ParserGenerator skipWhitespace() {
			return oneOfChars(whitespaceChars, "restartTextRange();");
		}

		ParserGenerator ignoreWhitespace() {
			return oneOfChars(whitespaceChars, " ");
		}

		ParserGenerator skipLineBreaks() {
			return oneOfChars(lineBreakChars, "restartTextRange();");
		}

		ParserGenerator ignoreLineBreaks() {
			return oneOfChars(lineBreakChars, " ");
		}

		ParserGenerator handleComments() {
			return charSequence("//", "finishParsingLineComment();")
			      .charSequence("/*", "finishParsingBlockComment();")
			      .charSequence("/+", "finishParsingNestingBlockComment();");
		}


		string generate() const {
			return whilePrefix ~ "while(true){" ~ code ~ "}";
		}

		//key - array of possible values for chars
		//key[i] - array of possible values for char #i
		//key[i][j] - one of possible values for char #i
		private ParserGenerator add(const(dchar[][]) key, string action) {
			if (key.length > 0) {
				foreach (c; key[0]) {
					if (c !in rules) rules[c] = ParserGenerator();
					rules[c].add(key[1..$], action);
				}
			} else {
				assert(this.action is null);
				this.action = action;
			}
			return this;
		}

		private string code() const {
			if (rules.length == 0) return action;
			string result = "switch(getCurrentCharAndAdvance()){";

			dchar[][string] codeToCharsMap;
			foreach (key, value; rules) {
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

	void error(dstring message, TextRange textRange = TextRange(previousPosition, position)) {
		if (isEOF()) {
			textRange.end = previousPosition;
		}
		textRange.text = text[textRange.begin.index .. textRange.end.index];
		auto error = new ParseError;
		error.message = std.conv.text(message);
		error.textRange = textRange;
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

	void finishParsingIdentifier() {
		while (isIdentifierChar(advance())) {}
	}

	auto finishParsingModuleDeclaration()
	in {
		//assert(moduleKeywordTextRange.text == "module");
		//assert(position == moduleKeywordTextRange.firstCharIndex + moduleKeywordTextRange.text.length);
	}
	body {
		auto d = new ModuleDeclaration;
		result.declarations ~= d;
		TextPosition moduleKeywordEnd = position;

		//mixin(generateParser!(ParserGenerator("P1").ignoreWhitespace().ignoreLineBreaks().handleComments()
		//	.identifierThatCanStartWithDigit(
		//		"d.packageNames ~= endTextRange();" ~
		//		ParserGenerator("P2").ignoreWhitespace().ignoreLineBreaks().handleComments()
		//			.oneOfChars(['.'], "break P2;")
		//			.oneOfChars([';'], "d.textRange = endTextRange(); break P1;")
		//			.oneOfChars([0], "error(`expected '.' or ';', found end of file`);         goToPreviousChar(); d.textRange = endTextRange(); if (!d.packageNames.empty) { d.textRange.end = d.packageNames[$-1].end; } else { d.textRange.end = moduleKeywordEnd; } break P1;")
		//			.noMatch(        "error(`expected '.' or ';', found '`d~previousChar~`'`); goToPreviousChar(); d.textRange = endTextRange(); if (!d.packageNames.empty) { d.textRange.end = d.packageNames[$-1].end; } else { d.textRange.end = moduleKeywordEnd; } break P1;")
		//			.generate()
		//	)
		//	.oneOfChars(['.'], "startTextRange(); d.packageNames ~= endTextRange();")
		//	.oneOfChars([';'], "startTextRange(); d.packageNames ~= endTextRange(); d.textRange = endTextRange(); break P1;")
		//	.oneOfChars([0], "error(`expected package name, found end of file`);         goToPreviousChar(); d.textRange = endTextRange(); if (!d.packageNames.empty) { d.textRange.end = d.packageNames[$-1].end; } else { d.textRange.end = moduleKeywordEnd; } break P1;")
		//	.noMatch(        "error(`expected package name, found '`d~previousChar~`'`); goToPreviousChar(); d.textRange = endTextRange(); if (!d.packageNames.empty) { d.textRange.end = d.packageNames[$-1].end; } else { d.textRange.end = moduleKeywordEnd; } break P1;")
		//));


		TextRange createTextRange(TextPosition begin, TextPosition end) {
			TextRange result;
			result.begin = begin;
			result.end = end;
			result.text = text[begin.index .. end.index];
			return result;
		}

		TextRange emptyRangeStartingFromPreviousChar() {
			return createTextRange(previousPosition, previousPosition);
		}

		TextRange parseIdentifierStartingFromPreviousChar() {
			TextPosition begin = previousPosition;
			while (isIdentifierChar(advance())) {}
			return createTextRange(begin, position);
		}

		void errorExpected(dstring expected) {
			if (previousChar == 0) {
				error(dtext(format("expected %s, found end of file", expected)));
			} else {
				error(dtext(format("expected %s, found '%c'", expected, previousChar)));
			}
		}

		bool shouldSkip(dchar c) {
			switch (c) {
				case'\U00000020':  // FIXME: move to advance()
				case'\U0000000C':
				case'\U00002028':
				case'\U00000009':
				case'\U0000000D':
				case'\U00002029':
				case'\U0000000A':
				case'\U0000000B':
					return true;
				default:
					return false;
			}
		}

		dchar advanceSkipping() {
			do {
				advance();
			} while (shouldSkip(previousChar));
			return previousChar;
		}

		while (true) {
			advanceSkipping();
			if (isIdentifierChar(previousChar)) {
				d.packageNames ~= parseIdentifierStartingFromPreviousChar();
				advanceSkipping();
				if (previousChar != '.') {
					if (previousChar != ';') {
						errorExpected("'.' or ';'");
						goToPreviousChar();
					}
					break;
				}
			} else if ((previousChar == '.') || (previousChar == ';')) {
				d.packageNames ~= emptyRangeStartingFromPreviousChar();
			} else {
				errorExpected("package name");
				goToPreviousChar();
			}
			if (!isIdentifierChar(previousChar) && (previousChar != '.')) break;
		}

		d.textRange = endTextRange();
		if (previousChar() != ';') {
			d.textRange.end = d.packageNames.empty ? moduleKeywordEnd : d.packageNames[$-1].end;
			d.textRange.text = text[d.textRange.begin.index .. d.textRange.end.index];
		}

		if (d.name.empty) {
			error(`no module name`, d.textRange);
		} else {
			if (!find!(packageName => packageName.empty || isDigit(packageName[0]))(d.packageNames).empty) {
				error("invalid module name", d.textRange);
			}
		}
	}// Todo missing dot test

	void finishParsingImportDeclaration() {
		void parseImportList(TextRange textRange) {
			assert(0);
		}

		startTextRange();
		mixin(generateParser!(ParserGenerator().ignoreWhitespace().ignoreLineBreaks().handleComments()
			.oneOfChars(identifierChars, "return parseImportList(endTextRange());")
			//.noMatch
		));
	}

	void parseDeclaration() {
		startTextRange();
		mixin(generateParser!(ParserGenerator().skipWhitespace().skipLineBreaks().handleComments()
			.keyword("module", "return finishParsingModuleDeclaration();", "return finishParsingIdentifier();")
			.keyword("import", "return finishParsingImportDeclaration();", "return finishParsingIdentifier();")
			.oneOfChars([0], "return;")
			.noMatch("/*error(`expected declaration`);*/ return;")
		));
	}


	while (!isEOF()) {
		parseDeclaration();
	}

	return result;
}

unittest {
	parse("");
}
