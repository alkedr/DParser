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

	auto result = new Module;



	void advancePositionNoSkip(ref TextPosition position) {
		auto current = text[position.index];
		if ((current == '\u0000') || (current == '\u001A')) return;
		auto next = text[position.index+1];

		if (((current == '\u000D') && (next != '\u000A')) ||
		    (current == '\u000A') || (current == '\u2028') || (current == '\u2028')) {
			position.line++;
			position.column = 0;
		}
		position.column++;
		position.index++;
	}

	void skipCrapForPosition(ref TextPosition position) {
		while ((text[position.index] == '\u000D') || (text[position.index] == '\u000A') ||
		       (text[position.index] == '\u2028') || (text[position.index] == '\u2029') ||
		       (text[position.index] == '\u0020') || (text[position.index] == '\u0009') ||
		       (text[position.index] == '\u000B') || (text[position.index] == '\u000C')) {
			advancePositionNoSkip(position);
		}
	}

	void advancePosition(ref TextPosition position) {
		advancePositionNoSkip(position);
		skipCrapForPosition(position);
	}

	TextPosition previousPosition;
	TextPosition currentPosition;
	TextPosition nextPosition;

	dchar previousChar() { return text[previousPosition.index]; }
	dchar  currentChar() { return text[ currentPosition.index]; }
	dchar     nextChar() { return text[    nextPosition.index]; }

	bool isEOF() { return (currentChar == '\u0000') || (currentChar == '\u001A'); }

	dchar previousCharNoSkip() {
		if (currentPosition.index == 0) return 0;
		return text[currentPosition.index-1];
	}

	dchar nextCharNoSkip() {
		if (isEOF()) return 0;
		return text[currentPosition.index+1];
	}

	void advance() {
		previousPosition = currentPosition;
		currentPosition = nextPosition;

		//writeln("new current char ", cast(int)currentChar);

		advancePosition(nextPosition);
	}

	void advanceNoSkip() {
		previousPosition = currentPosition;
		advancePositionNoSkip(currentPosition);
		if (currentPosition == nextPosition) advancePosition(nextPosition);
	}

	void skipCrap() {
		skipCrapForPosition(currentPosition);
		nextPosition = currentPosition;
		advancePosition(nextPosition);
	}

/*
	// new range starts with current char
	void startTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length), __FUNCTION__, " ", currentPosition);
		TextRange textRange;
		textRange.begin = currentPosition;
		textRangeStack ~= textRange;
	}

	ref TextRange currentTextRange() {
		assert(textRangeStack.length > 0);
		return textRangeStack[$-1];
	}

	// range starts with current char
	void restartTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", currentPosition);
		currentTextRange().begin = currentPosition;
	}

	// range starts with previous char
	void restartTextRangeIncludingPreviousChar() {
		currentTextRange().begin = previousPosition;
	}

	// range ends with previous char
	TextRange endTextRange() {
		//writeln(std.array.replicate("  ", textRangeStack.length-1), __FUNCTION__, " ", currentPosition);
		TextRange result = currentTextRange();
		textRangeStack = textRangeStack[0..$-1];
		result.end = currentPosition;
		result.text = text[result.begin.index .. result.end.index];
		return result;
	}
*/


	struct ParserGenerator {
		ParserGenerator[dchar] rules;
		string action = "";

		ParserGenerator onCharSequence(const dchar[] chars, string action) {
			if (chars.length > 0) {
				if (chars[0] !in rules) rules[chars[0]] = ParserGenerator();
				rules[chars[0]].onCharSequence(chars[1..$], action);
			} else {
				this.action ~= action;
			}
			return this;
		}

		ParserGenerator onKeyword(const dchar[] chars, string actionOnMatch, string actionOnMismatch) {
			return onCharSequence(chars,
				"if(isIdentifierChar(currentChar())){" ~ actionOnMismatch ~ "}else{" ~ actionOnMatch ~ "}"
			);
		}

		ParserGenerator onNoMatch(string action) {
			this.action ~= action;
			return this;
		}

		private string code() const {
			if (rules.length == 0) return action;
			auto result = "{switch(currentChar()){";
			foreach (key, value; rules) {
				result ~= format(`case'\U%08X':{advanceNoSkip();%s}break;`, key, value.code);
			}
			return result ~ format(`default:{advanceNoSkip();%s}break;}}`, action);
		}
	}

	template generateParser(rulesTuple...) {
		immutable string generateParser = rulesTuple[0].code;
	}


	bool isIdentifierChar(dchar c) {
		return isAlphaNum(c) || (c == '_');
	}

	bool isWhitespaceChar(dchar c) {
		return (c == '\u0020') || (c == '\u0009') || (c == '\u000B') || (c == '\u000C');
	}

	void error(string message, TextRange textRange = TextRange(previousPosition, currentPosition)) {
		if (textRange.end.index >= text.length-1) {
			assert(isEOF);
			textRange.end = currentPosition;
		}
		textRange.text = text[textRange.begin.index .. textRange.end.index];
		auto error = new ParseError;
		error.message = message;
		error.textRange = textRange;
		result.errors ~= error;
	}

	void errorExpected(string message) {
		TextRange textRange = TextRange(currentPosition, currentPosition);
		if (currentChar == 0) {
			error(format("expected " ~ message ~ ", found end of file"), textRange);
		} else {
			advancePositionNoSkip(textRange.end);
			error(format("expected " ~ message ~ ", found '%c'", currentChar), textRange);
		}
	}

	void errorExpectedChars(dchar[] chars) {
		assert(!chars.empty);
		string message;
		if (chars.length == 1) {
			message = format("'%c'", chars[0]);
		} else if (chars.length == 2) {
			message = format("'%c' or '%c'", chars[0], chars[1]);
		} else if (chars.length == 3) {
			foreach (c; chars[0..$-2]) {
				message = format("'%c', ", c);
			}
			message ~= format("'%c' or '%c'", chars[0], chars[1], chars[2]);
		}

		errorExpected(message);
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

	TextRange parseIdentifier() {
		skipCrap();
		//writeln(__FUNCTION__, " ", currentChar);
		TextRange result;
		result.begin = currentPosition;
		while (isIdentifierChar(currentChar)) {  // TODO: can't start with digit
			advanceNoSkip();
		}
		result.end = currentPosition;
		result.text = text[result.begin.index .. result.end.index];
		skipCrap();
		//writeln(__FUNCTION__, " ", result.text);
		return result;
	}

	bool parseChar(dchar c) {
		if (currentChar == c) {
			advanceNoSkip();
			return true;
		} else {
			return false;
		}
	}

	void finishParsingModuleDeclaration(TextPosition begin)
	in {
		//assert(moduleKeywordTextRange.text == "module");
		//assert(currentPosition == moduleKeywordTextRange.firstCharIndex + moduleKeywordTextRange.text.length);
	}
	body {
		auto d = new ModuleDeclaration;
		d.textRange.begin = begin;
		d.textRange.end = currentPosition;
		result.declarations ~= d;

		do {
			d.packageNames ~= parseIdentifier();
		} while (parseChar('.'));

		if (parseChar(';')) {
			d.textRange.end = currentPosition;
		} else {
			errorExpectedChars(['.', ';']);
			if (!d.name.empty) {
				d.textRange.end = d.packageNames[$-1].end;
			}
		}

		d.textRange.text = text[d.textRange.begin.index .. d.textRange.end.index];

		if (d.name.empty) {
			error(`no module name`, d.textRange);
		} else {
			if (!find!(packageName => packageName.empty || isDigit(packageName[0]))(d.packageNames).empty) {
				error("invalid module name", d.textRange);
			}
		}
	}// Todo missing dot test

	void finishParsingImportDeclaration(TextPosition begin) {
		/*void parseImportList(TextRange textRange) {
			assert(0);
		}

		startTextRange();
		mixin(generateParser!(ParserGenerator().ignoreWhitespace().ignoreLineBreaks().handleComments()
			.oneOfChars(identifierChars, "return parseImportList(endTextRange());")
			//.noMatch
		));*/
	}

	//writeln(ParserGenerator()
	//		.onKeyword("module", "return finishParsingModuleDeclaration();", "return finishParsingIdentifier();")
	//		.onKeyword("import", "return finishParsingImportDeclaration();", "return finishParsingIdentifier();")
	//		.onNoMatch("/*error(`expected declaration`);*/ writeln(`onNoMatch`) return;").code);

	void parseDeclaration() {
		skipCrap();
		TextPosition begin = currentPosition;
		mixin(generateParser!(ParserGenerator()
			.onKeyword("module", "return finishParsingModuleDeclaration(begin);", "")
			.onKeyword("import", "return finishParsingImportDeclaration(begin);", "")
			.onNoMatch("/*error(`expected declaration`);*/ return;")
		));
	}

	//writeln("initial nextPosition.index: ", nextPosition.index);
	while (!isEOF()) {
		parseDeclaration();
	}

	return result;
}

unittest {
	parse("");
}
