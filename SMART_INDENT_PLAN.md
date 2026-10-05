# Indentação inteligente com Tree-sitter

## Contexto

Hoje o ENTER do Opus copia a indentação da linha de cima e nada mais
(`CursorCollection.compute_enter_edits`). Com a árvore sintática já
disponível, dá para fazer o que o VS Code faz:

1. **ENTER abre um nível** depois de algo que abre um bloco
   (`def foo(arg)|` → linha nova um nível adentro).
2. **Digitar um fechamento recua a linha** (`end`, `}`, `else`… como
   primeira coisa da linha).

Os dois valem **por cursor**: com vários cursores, cada um recebe a
indentação do seu próprio contexto.

O Helix tem um `indents.scm` por linguagem que descreve isso, e a nossa
convenção de queries já é a dele.

## Comportamento esperado

| Situação | Resultado |
|---|---|
| `def foo(arg)\|` + ENTER | linha nova com um nível a mais |
| `  puts arg\|` + ENTER | linha nova no mesmo nível |
| `foo(\|` + ENTER | um nível a mais (argumentos) |
| `def foo(arg)\|` e `bar\|` (dois cursores) + ENTER | o primeiro ganha um nível, o segundo não |
| Linha `  ` + digitar `end` | a linha recua um nível ao completar `end` |
| `puts "the end"` | nada: `end` não é a primeira coisa da linha |
| Linguagem sem `indents.scm`, árvore ainda em análise, ou linha em branco | ENTER de hoje (copia a indentação) |

## Como o cálculo funciona

Regras do Helix (`helix-core/src/indent.rs`, `book/src/guides/indent.md`):

- O nível de uma linha é o número de escopos `@indent` que a contêm. O
  escopo de um nó vai da linha **seguinte** à primeira dele até a última.
- Vários escopos que abrem na mesma linha contam como um só.
- `@outdent` tira um nível da linha em que o nó começa.
- `@indent.always` / `@outdent.always` não colapsam.
- Um nó com `@indent` e `@outdent` ao mesmo tempo não conta.
- `(#set! "scope" "header")` faz o escopo começar na linha do nó pai
  (corpos sem chaves em C, Java, JS).

**Sempre relativo, nunca absoluto** (o modo "hybrid" do Helix): calcula
o nível da linha nova e o da linha atual pela árvore, e soma a
**diferença** à indentação real da linha atual. Assim um arquivo
indentado fora do padrão, ou uma query incompleta, não bagunça a linha.

Para a linha nova, as posições dos nós são ajustadas como se a quebra já
existisse: um nó que termina exatamente no cursor não contém a linha
nova; um que continua depois dele, contém.

**Fora desta entrega**, por serem casos especiais que pedem bem mais
código: `@align`/`@anchor` (alinhar argumentos na coluna do parêntese),
`@extend` (Python: recuar depois de `return`) e `@opaque` (não mexer em
strings de várias linhas). Linguagens cujas queries dependem deles
continuam funcionando nos casos comuns; esses captures são ignorados.

## Arquitetura

Segue o padrão das fases anteriores: lógica em Models, a View só liga.

**Binding** (`vapi/tree-sitter.vapi`): `Node.parent()`, `Node.id`,
`Node.descendant_for_byte_range()`, `QueryCursor.set_byte_range()`.

**Models** (`src/models/syntax/`):

| Arquivo | Mudança |
|---|---|
| `query-predicates.vala` | Quatro predicados das queries de indentação: `#kind-eq?`, `#same-line?`, `#one-line?` e as formas `not-`. `accepts()` ganha a posição da quebra de linha, para as comparações de linha valerem no texto já quebrado |
| `loaded-language.vala` | Carrega `queries/indents.scm` (opcional): query, predicados, papel de cada captura, padrões com `scope "header"` |
| `syntax-indents.vala` (novo) | O cálculo: nível de uma linha existente, nível de uma linha nova, e "esta linha começa com um token de recuo?" |
| `syntax-document.vala` | `new_line_indent_change (offset)` e `outdent_change (offset)`: escolhem a camada mais interna que tem `indents.scm` (o JS de um `<script>`, não o HTML) e devolvem a diferença de níveis; 0 quando não há o que dizer |
| `language-checker.vala` | Passa a validar `indents.scm` |

**Edição** (`src/models/cursor-collection.vala`):

- `compute_enter_edits` ganha um parâmetro opcional: uma função que,
  dada a posição de um cursor, devolve quantos níveis somar. Sem ela, o
  comportamento é o de hoje, e os testes atuais não mudam.
- Novo `compute_outdent_edits`: para cada cursor cuja linha acabou de
  passar a começar com um token de recuo, ajusta só o espaço em branco
  inicial daquela linha.
- A conversão nível → espaços/tabs reaproveita `visible_column` e a
  regra de `normalize_indentation`, respeitando `indent_size` e
  `insert_spaces` do `.editorconfig`.

**View** (`src/views/components/code-editor/`):

- `_syntax-highlighter.vala`: expõe as duas consultas, garantindo antes
  que o documento está em dia com o buffer; com o parse ainda em fatias,
  responde 0.
- `_cursors.vala`: `enter()` passa a função ao Model. `type_char()`,
  depois de aplicar o caractere, pede o recuo e o aplica **na mesma
  transação de desfazer**, para um Ctrl+Z desfazer os dois juntos.
- `index.vala`: liga cursores e highlighter (os dois são subcomponentes
  do `CodeEditor`, que é quem conhece ambos).

**Pacotes**:

- `tools/port-helix-language.py` passa a copiar `indents.scm`; reimportar
  os pacotes existentes traz as queries do Helix.
- `languages/vala/queries/indents.scm`: escrito à mão (blocos `{}`,
  parênteses, colchetes, `case`), já que o Helix não tem. O script não o
  apaga: ele só sobrescreve o que existe no Helix.
- SQL fica sem, com o ENTER de hoje.
- `docs/LANGUAGE_PACKAGES.md`: seção de `indents.scm`.

## Etapas

Cada uma termina compilando sem warnings novos, com os testes passando.

1. **Base.** Binding, predicados, carga de `indents.scm`, reimportação
   dos pacotes, teste dos pacotes embutidos validando as queries novas.
2. **ENTER.** `syntax-indents`, `SyntaxDocument.new_line_indent_change`,
   parâmetro em `compute_enter_edits`, ligação na View. Já entrega o
   primeiro exemplo, com multicursor.
3. **Recuo ao digitar.** `outdent_change`, `compute_outdent_edits`,
   ligação em `type_char()` na mesma transação.
4. **Vala e guia.** `indents.scm` de Vala e documentação.

## Riscos

- **Árvore inválida no momento do ENTER.** `def foo(arg)` sem `end` é
  código quebrado. Se o Tree-sitter fechar o `method` exatamente no
  cursor, ele não "contém" a linha nova e o nível não sobe. É o primeiro
  caso a testar com a gramática real de Ruby; se falhar, a etapa 2
  precisa de uma regra extra para nós que terminam num token ausente.
- **Recuo indevido.** A regra "só quando o token é a primeira coisa da
  linha, e só nessa linha" precisa de teste negativo explícito.
- **Árvore desatualizada.** Depois de `type_char`, o documento tem de
  ser atualizado antes de consultar o recuo; isso é um parse incremental
  síncrono por tecla, o mesmo que o highlight já faz em seguida.
- **Queries do Helix com predicados ou capturas fora do previsto.** O
  teste dos pacotes embutidos acusa na etapa 1.

## Verificação

- **Models**: `tests/models/syntax/syntax-document-test.vala` com a
  gramática real de Ruby e de JavaScript (ENTER após `def`, após linha
  comum, dentro de argumentos, em bloco `{`; recuo com `end` e `}`;
  caso negativo). `tests/models/cursor-collection-test.vala` para a
  aplicação dos níveis com espaços e com tabs, e para vários cursores.
- **Sistema**: `tests/system/editing/enter-indent-test.vala` ganha os
  dois exemplos de multicursor da conversa, e um teste de digitar `end`
  com Ctrl+Z desfazendo tudo de uma vez.
- **Manual**: `just run tests/examples` e repetir os exemplos em Ruby,
  JavaScript, Python e Vala.
- `meson test -C out/native` inteiro antes de dar por pronto.
