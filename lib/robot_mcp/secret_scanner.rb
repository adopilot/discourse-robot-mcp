# frozen_string_literal: true

module ::RobotMcp
  # Finds things that look like passwords, keys or tokens in text before it is
  # published. Reports only the kind and line number, never the secret itself.
  module SecretScanner
    KEYWORD =
      /\b(?:pass(?:word|wd)?|pwd|lozink\p{L}*|šifr\p{L}*|sifr\p{L}*|secret|token|api[_ -]?key|apikey|client[_ -]?secret|psk|wpa[_ -]?key|pre[_ -]?shared[_ -]?key|snmp[_ -]?community)\b\s*[:=]\s*(.*)/i

    # Values that are clearly not a secret ("lozinka: u trezoru", "password: ***").
    PLACEHOLDER =
      /\A(?:$|u trezoru|trezor|vault|\*+|x{3,}|<[^>]*>|\[[^\]]*\]|\([^)]*\)|\{\{[^}]*\}\}|skriven|redacted|nije navedena|ne pi[sš]e|n\/a|-+|"?\$\{?[A-Z_]+\}?"?)/i

    PATTERNS = {
      "privatni ključ" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
      "lozinka u URL-u" => %r{\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s@/]+@}i,
      "Cisco lozinka" => /\b(?:secret|password)\s+[057]\s+\S+/i,
      "Anthropic/OpenAI ključ" => /\bsk-[A-Za-z0-9_-]{20,}/,
      "AWS ključ" => /\bAKIA[0-9A-Z]{16}\b/,
      "GitHub token" => /\bgh[pousr]_[A-Za-z0-9]{30,}/,
      "Slack token" => /\bxox[abprs]-[A-Za-z0-9-]{10,}/,
      "JWT token" => /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\./,
    }.freeze

    module_function

    def scan(text)
      findings = []
      text
        .to_s
        .each_line
        .with_index(1) do |line, number|
          if (match = KEYWORD.match(line)) && !PLACEHOLDER.match?(match[1].strip)
            findings << { kind: "lozinka/ključ uz ključnu riječ", line: number }
          end
          PATTERNS.each do |kind, pattern|
            findings << { kind: kind, line: number } if pattern.match?(line)
          end
        end
      findings.uniq
    end

    def ensure_clean!(*texts)
      findings = texts.flat_map { |text| scan(text) }
      return if findings.empty?

      summary = findings.map { |f| "#{f[:kind]} (red #{f[:line]})" }.uniq.join(", ")
      raise DiscourseMcp::ToolError,
            "Objava odbijena: tekst izgleda kao da sadrži tajne podatke: #{summary}. " \
              "Ukloni vrijednosti i umjesto njih ostavi prazno mjesto za trezor, npr. " \
              "lozinka: [vault ask=\"Router admin\"], pa pokušaj ponovo."
    end
  end
end
