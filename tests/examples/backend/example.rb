Locale = Struct.new(:code, :name)

LOCALES = [
  Locale.new("en", "English"),
  Locale.new("pt-BR", "Português"),
].freeze

def find_locale(code)
  LOCALES.find { |locale| locale.code.casecmp?(code) }
end

def requested_locale(accept_language)
  tags = accept_language.split(",").map { |tag| tag.split(";").first.strip }

  tags.each do |tag|
    match = find_locale(tag) || find_locale(tag.split("-").first)
    
    return match if match
  end

  nil
end

match = requested_locale("pt-BR,pt;q=0.9,en;q=0.8")
puts match ? match.name : "no match"