module parser;

public import ast;

import std.ascii;
import std.string : format;
import std.array;
import std.stdio;
import std.algorithm;


public class ParseError : TextRange {
	string message;
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

	TextPosition currentPosition;

	dchar currentChar() { return text[ currentPosition.index]; }

	bool isEOF() { return (currentChar == '\u0000') || (currentChar == '\u001A'); }

	void advance() {
		advancePosition(currentPosition);
	}

	void advanceNoSkip() {
		advancePositionNoSkip(currentPosition);
	}

	void skipCrap() {
		skipCrapForPosition(currentPosition);
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


	void error(string message, TextRange textRange) {
		if (textRange.end.index >= text.length-1) {
			assert(isEOF);
			textRange.end = currentPosition;
		}
		auto e = new ParseError;
		e.wholeText = text;
		e.begin = textRange.begin;
		e.end = textRange.end;
		e.message = message;
		m.errors ~= e;
	}

	void errorExpected(string message) {
		TextRange textRange = new TextRange(text, currentPosition, currentPosition);
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


	T startParsing(T)(const ref TextPosition begin = currentPosition) {
		skipCrap();
		auto t = new T;
		t.wholeText = text;
		t.begin = begin;
		t.end = currentPosition;
		return t;
	}

	T endParsing(T)(T t, TextPosition end = currentPosition) {
		t.end = end;
		if (t.begin.index > t.end.index) {
			t.begin = t.end;
		}
		skipCrap();
		return t;
	}

	Identifier parseIdentifier() {
		auto result = startParsing!(Identifier);
		if (isAlpha(currentChar) || (currentChar == '_')) {
			while (isAlphaNum(currentChar) || (currentChar == '_')) {  // TODO: can't start with digit
				advanceNoSkip();
			}
			return endParsing(result);
		} else {
			return endParsing(result, result.begin);
		}
	}


	void parseDeclaration() {

		T startParsingDeclaration(T)(const ref TextPosition begin = currentPosition) {
			auto d = startParsing!(T)(begin);
			m.declarations ~= d;
			return d;
		}

		ModuleName finishParsingModuleName(Identifier firstPart) {
			auto moduleName = startParsing!(ModuleName)(firstPart.begin);
			skipCrapForPosition(moduleName.begin);
			moduleName.parts ~= firstPart;
			while (currentChar == '.') {
				advanceNoSkip();
				moduleName.parts ~= parseIdentifier();
			}
			return endParsing(moduleName, moduleName.parts[$-1].end);
		}

		ModuleName parseModuleName() {
			return finishParsingModuleName(parseIdentifier());
		}

		void finishParsingModuleDeclaration(TextPosition begin) {
			auto d = startParsingDeclaration!(ModuleDeclaration)(begin);

			d.name = parseModuleName();

			if (currentChar != ';') {
				errorExpectedChars(['.', ';']);
				if (!d.name.empty) {
					endParsing(d, d.name.parts[$-1].end);
				}
			} else {
				advanceNoSkip();
				endParsing(d);
			}

			if (d.name.empty) {
				error(`no module name`, d);
			} else {
				if (!find!(packageName => packageName.textInRange.empty || isDigit(packageName.textInRange[0]))(d.name.parts).empty) {
					error("invalid module name", d);
				}
			}
		}

		Import parseImport() {
			auto i = startParsing!(Import);
			auto identifier = parseIdentifier();
			if (currentChar == '=') {
				advanceNoSkip();
				i.aliasName = identifier;
				i.moduleName = parseModuleName();
			} else {
				i.moduleName = finishParsingModuleName(identifier);
			}
			if (currentChar == ':') {
				advanceNoSkip();
				do {
					auto symbolNameOrAlias = parseIdentifier();
					auto symbol = startParsing!(ImportSymbol)(symbolNameOrAlias.begin);
					if (currentChar == '=') {
						advanceNoSkip();
						symbol.aliasName = symbolNameOrAlias;
						symbol.name = parseIdentifier();
					} else {
						symbol.name = symbolNameOrAlias;
					}
					i.symbols ~= endParsing(symbol, symbol.name.end);
					if (currentChar != ',') break;
					advanceNoSkip();
				} while (true);
			}
			return endParsing(i);
		}

		void finishParsingImportDeclaration(TextPosition begin, bool isStatic) {
			auto d = startParsingDeclaration!(ImportDeclaration)(begin);
			d.isStatic = isStatic;

			do {
				d.imports ~= parseImport();
				if (currentChar != ',') break;
				advanceNoSkip();
			} while (true);

			if (currentChar == ';') {
				advanceNoSkip();
			} else  {
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
