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

	this(dstring text) {
		this.text = text;
	}
}


Module parse(dstring text) {
	text ~= 0;

	Module m = new Module(text);


	void advanceCursorNoSkip(ref Cursor currentCursor) {
		auto current = text[currentCursor.index];
		if ((current == '\u0000') || (current == '\u001A')) return;
		auto next = text[currentCursor.index+1];

		if (((current == '\u000D') && (next != '\u000A')) ||
		    (current == '\u000A') || (current == '\u2028') || (current == '\u2028')) {
			currentCursor.line++;
			currentCursor.column = 0;
		}
		currentCursor.column++;
		currentCursor.index++;
	}

	void skipLineComment() {
	}

	void skipBlockComment() {
	}

	void skipNestingBlockComment() {
	}

	void skipCrapForCursor(ref Cursor currentCursor) {
		while (true) {
			switch (text[currentCursor.index]) {
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
					switch (text[currentCursor.index+1]) {
						case '/': skipLineComment();
						case '*': skipBlockComment();
						case '+': skipNestingBlockComment();
						default: return;
					}

				default: return;
			}
			advanceCursorNoSkip(currentCursor);
		}
	}

	void advanceCursor(ref Cursor currentCursor) {
		advanceCursorNoSkip(currentCursor);
		skipCrapForCursor(currentCursor);
	}

	Cursor currentCursor;

	dchar currentChar() { return text[ currentCursor.index]; }

	bool isEOF() { return (currentChar == '\u0000') || (currentChar == '\u001A'); }

	void advance() {
		advanceCursor(currentCursor);
	}

	void advanceNoSkip() {
		advanceCursorNoSkip(currentCursor);
	}

	void skipCrap() {
		skipCrapForCursor(currentCursor);
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

		ParserGenerator onKeyword(const dchar[] chars, string action) {
			return onCharSequence(chars, "if(!isAlphaNum(currentChar)&&(currentChar!='_')){" ~ action ~ "}");
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
			textRange.end = currentCursor;
		}
		auto e = new ParseError;
		e.wholeText = text;
		e.begin = textRange.begin;
		e.end = textRange.end;
		e.message = message;
		m.errors ~= e;
	}

	void errorExpected(string what) {
		TextRange textRange = new TextRange(text, currentCursor, currentCursor);
		if (currentChar == 0) {
			error(format("expected " ~ what ~ ", found end of file"), textRange);
		} else {
			advanceCursorNoSkip(textRange.end);
			error(format("expected " ~ what ~ ", found '%c'", currentChar), textRange);
		}
	}

	void errorExpectedChars(const dchar[] chars) {
		assert(!chars.empty);
		string message = format("'%c'", chars[0]);
		if (chars.length > 2) {
			foreach (c; chars[0..$-2]) {
				message ~= format(", '%c'", c);
			}
		}
		if (chars.length > 1) {
			message ~= format(" or '%c'", chars[$-1]);
		}
		errorExpected(message);
	}


	T startParsing(T)(const ref Cursor begin = currentCursor) {
		skipCrap();
		auto t = new T;
		t.wholeText = text;
		t.begin = begin;
		t.end = currentCursor;
		return t;
	}

	T endParsing(T)(T t, Cursor end = currentCursor) {
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
			while (isAlphaNum(currentChar) || (currentChar == '_')) {
				advanceNoSkip();
			}
			return endParsing(result);
		} else {
			return endParsing(result, result.begin);
		}
	}


	void parseDeclaration() {

		T startParsingDeclaration(T)(const ref Cursor begin = currentCursor) {
			auto d = startParsing!(T)(begin);
			m.declarations ~= d;
			return d;
		}

		ModuleName finishParsingModuleName(Identifier firstPart) {
			auto moduleName = startParsing!(ModuleName)(firstPart.begin);
			skipCrapForCursor(moduleName.begin);
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

		void finishParsingModuleDeclaration(Cursor begin) {
			auto keywordEnd = currentCursor;
			auto d = startParsingDeclaration!(ModuleDeclaration)(begin);

			d.name = parseModuleName();

			if (currentChar != ';') {
				errorExpectedChars(['.', ';']);
				if (d.name.empty) {
					endParsing(d, keywordEnd);
				} else {
					endParsing(d, d.name.parts[$-1].end);
				}
			} else {
				advanceNoSkip();
				endParsing(d);
			}

			if (d.name.empty) {
				error(`no module name`, d);
			} else {
				if (!d.name.parts.find!(packageName => packageName.textInRange.empty || isDigit(packageName.textInRange[0])).empty) {
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

		void finishParsingImportDeclaration(Cursor begin, bool isStatic) {
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

		void parsedBasicType(Cursor begin, BasicType basicType) {

		}

		skipCrap();
		Cursor begin = currentCursor;
		mixin(generateParser!(ParserGenerator()
			.onKeyword("module", "return finishParsingModuleDeclaration(begin);")
			.onKeyword("import", "return finishParsingImportDeclaration(begin, false);")

			.onKeyword("void",    "return parsedBasicType(begin, BasicType.VOID);"   )
			.onKeyword("bool",    "return parsedBasicType(begin, BasicType.BOOL);"   )
			.onKeyword("byte",    "return parsedBasicType(begin, BasicType.BYTE);"   )
			.onKeyword("ubyte",   "return parsedBasicType(begin, BasicType.UBYTE);"  )
			.onKeyword("short",   "return parsedBasicType(begin, BasicType.SHORT);"  )
			.onKeyword("ushort",  "return parsedBasicType(begin, BasicType.USHORT);" )
			.onKeyword("int",     "return parsedBasicType(begin, BasicType.INT);"    )
			.onKeyword("uint",    "return parsedBasicType(begin, BasicType.UINT);"   )
			.onKeyword("long",    "return parsedBasicType(begin, BasicType.LONG);"   )
			.onKeyword("ulong",   "return parsedBasicType(begin, BasicType.ULONG);"  )
			.onKeyword("char",    "return parsedBasicType(begin, BasicType.CHAR);"   )
			.onKeyword("wchar",   "return parsedBasicType(begin, BasicType.WCHAR);"  )
			.onKeyword("dchar",   "return parsedBasicType(begin, BasicType.DCHAR);"  )
			.onKeyword("float",   "return parsedBasicType(begin, BasicType.FLOAT);"  )
			.onKeyword("double",  "return parsedBasicType(begin, BasicType.DOUBLE);" )
			.onKeyword("real",    "return parsedBasicType(begin, BasicType.REAL);"   )
			.onKeyword("ifloat",  "return parsedBasicType(begin, BasicType.IFLOAT);" )
			.onKeyword("idouble", "return parsedBasicType(begin, BasicType.IDOUBLE);")
			.onKeyword("ireal",   "return parsedBasicType(begin, BasicType.IREAL);"  )
			.onKeyword("cfloat",  "return parsedBasicType(begin, BasicType.CFLOAT);" )
			.onKeyword("cdouble", "return parsedBasicType(begin, BasicType.CDOUBLE);")
			.onKeyword("creal",   "return parsedBasicType(begin, BasicType.CREAL);"  )

			.onNoMatch("return;")
		));
	}

	while (!isEOF()) {
		parseDeclaration();
	}
	return m;
}
