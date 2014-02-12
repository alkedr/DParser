module parser;

public import ast;

import std.ascii;
import std.string : format;
import std.array;
import std.stdio;
import std.algorithm;


public struct ParseError {
	const string message;
	const TextRange textRange;
}

public class Module {
	Declaration[] declarations;
	ParseError[] errors;
	dstring text;
}


Module parse(dstring text) {
	text ~= 0;

	Module m = new Module;
	m.text = text;


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

	void skipLineComment() {
	}

	void skipBlockComment() {
	}

	void skipNestingBlockComment() {
	}

	void skipCrapForPosition(ref TextPosition position) {
		while (true) {
			switch (text[position.index]) {
				case '\u000D':
				case '\u000A':
				case '\u2028':
				case '\u2029':
				case '\u0020':
				case '\u0009':
				case '\u000B':
				case '\u000C':
					break;

				case '/':
					switch (text[position.index+1]) {
						case '/': skipLineComment();
						case '*': skipBlockComment();
						case '+': skipNestingBlockComment();
						default: return;
					}

				default: return;
			}
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
				"if(isAlphaNum(currentChar)||(currentChar=='_')){" ~ actionOnMismatch ~ "}else{" ~ actionOnMatch ~ "}"
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


	void error(string message, TextRange textRange = TextRange(text, previousPosition, currentPosition)) {
		if (textRange.end.index >= text.length-1) {
			assert(isEOF);
			textRange.end = currentPosition;
		}
		m.errors ~= ParseError(message, textRange);
	}

	void errorExpected(string message) {
		TextRange textRange = TextRange(text, currentPosition, currentPosition);
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


	Identifier parseIdentifier() {
		skipCrap();
		auto begin = currentPosition;
		while (isAlphaNum(currentChar) || (currentChar == '_')) {  // TODO: can't start with digit
			advanceNoSkip();
		}
		auto end = currentPosition;
		skipCrap();
		auto result = new Identifier;
		result.textRange = TextRange(text, begin, end);
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





	void parseDeclaration() {

		T startParsing(T)(const ref TextPosition begin = currentPosition) {
			skipCrap();
			auto t = new T;
			t.textRange = TextRange(text, begin, currentPosition);
			return t;
		}

		T startParsingDeclaration(T)(const ref TextPosition begin = currentPosition) {
			auto d = startParsing!(T)(begin);
			m.declarations ~= d;
			return d;
		}

		T endParsing(T)(T t, TextPosition end = previousPosition) {
			advancePositionNoSkip(end);
			if (t.textRange.begin.index > end.index) {
				t.textRange.begin = end;
			}
			t.textRange.end = end;
			skipCrap();
			return t;
		}

		ModuleName finishParsingModuleName(Identifier firstPart) {
			auto moduleName = startParsing!(ModuleName)(firstPart.begin);
			moduleName.parts ~= firstPart;
			while (parseChar('.')) {
				moduleName.parts ~= parseIdentifier();
			}
			return endParsing(moduleName);
		}

		ModuleName parseModuleName() {
			return finishParsingModuleName(parseIdentifier());
		}

		void finishParsingModuleDeclaration(TextPosition begin) {
			auto d = startParsingDeclaration!(ModuleDeclaration)(begin);

			d.name = parseModuleName();

			if (!parseChar(';')) {
				errorExpectedChars(['.', ';']);
				if (!d.name.empty) {
					d.textRange.end = d.name.parts[$-1].textRange.end;
				}
			}

			endParsing(d);

			if (d.name.empty) {
				error(`no module name`, d.textRange);
			} else {
				if (!find!(packageName => packageName.textRange.empty || isDigit(packageName.textRange[0]))(d.name.parts).empty) {
					error("invalid module name", d.textRange);
				}
			}
		}

		Import parseImport() {
			auto i = startParsing!(Import);
			auto identifier = parseIdentifier();
			if (parseChar('=')) {
				i.aliasName = identifier;
				i.moduleName = parseModuleName();
			} else {
				i.moduleName = finishParsingModuleName(identifier);
			}
			if (parseChar(':')) {
				do {
					auto symbolNameOrAlias = parseIdentifier();
					auto symbol = startParsing!(ImportSymbol)(symbolNameOrAlias.textRange.begin);
					if (parseChar('=')) {
						symbol.aliasName = symbolNameOrAlias;
						symbol.name = parseIdentifier();
					} else {
						symbol.name = symbolNameOrAlias;
					}
					i.symbols ~= endParsing(symbol);
				} while (parseChar(','));
			}
			return endParsing(i, previousPosition);
		}

		void finishParsingImportDeclaration(TextPosition begin, bool isStatic) {
			auto d = startParsingDeclaration!(ImportDeclaration)(begin);
			d.isStatic = isStatic;

			do {
				d.imports ~= parseImport();
			} while (parseChar(','));

			if (!parseChar(';')) {
				//error
			}

			endParsing(d);
		}

		skipCrap();
		TextPosition begin = currentPosition;
		mixin(generateParser!(ParserGenerator()
			.onKeyword("module", "return finishParsingModuleDeclaration(begin);", "")
			.onKeyword("import", "return finishParsingImportDeclaration(begin, false);", "")
			.onNoMatch("return;")
		));
	}

	while (!isEOF()) {
		parseDeclaration();
	}
	return m;
}

