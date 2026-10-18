# Ambiente de experimentação QA

O i-Diário é uma aplicação Rails com PostgreSQL, separação de bancos por entidade,
autenticação Devise e processamento de tarefas com Sidekiq/Redis. O cadastro escolar
normalmente chega do i-Educar; os diários, planejamentos, PEIs e acompanhamentos são
mantidos no i-Diário. Relatórios e painéis consultam esses registros e algumas views
materializadas. As rotas estão em `config/routes.rb`, as regras em `app/models` e
os processos de integração em `app/services` e `app/workers`.

## Executar e acessar

Na raiz do projeto, com Docker Desktop aberto:

```powershell
docker compose up -d --no-build postgres redis puma
docker compose exec -T -e DISABLE_SPRING=1 puma bundle exec rake qa:seed qa:verify
```

Acesse http://localhost:3000. Para a carga de 2026:

| Perfil | Login | Senha padrão |
| --- | --- | --- |
| Professor | `qa.professor.2026` | `QaTeste2026!` |
| Gestor | `qa.gestor.2026` | `QaTeste2026!` |

Os logins acompanham o ano corrente. É possível definir outra senha passando
`-e QA_PASSWORD=...` ao container na primeira execução e na verificação.
O usuário `admin` existente mantém suas credenciais. A entidade padrão é
`prefeitura`; outra entidade pode ser selecionada com `NAME=nome` após a tarefa rake.

Selecione **QA Escola Laboratório 2026**, ano **2026**, turno **Matutino** e uma
das turmas **QA 6º A** ou **QA 2º A**. O professor já começa no contexto da primeira
turma e de Língua Portuguesa. Use o seletor de contexto para alternar turma e disciplina.
A tarefa imprime o período exato dos registros: os dez últimos dias letivos até hoje.
Use esse intervalo e a etapa correspondente nos filtros de diários e relatórios.

## Cobertura e roteiro

| Função | Dados e experimentação |
| --- | --- |
| Usuários, perfis e permissões | Professor com permissões próprias e gestor com perfil administrativo. Comparar menus e acesso às configurações. E-mails fictícios em `example.org`. |
| Escolas, cursos, séries, turmas, disciplinas e professores | Uma escola, um curso, duas séries, duas turmas, duas disciplinas e uma professora com quatro vínculos. Pesquisar por `QA`. |
| Alunos e matrículas | 24 alunos fictícios, 12 por turma, com matrículas e enturmações desde janeiro. Conferir listagens e filtros. |
| Calendário escolar | Quatro etapas e feriados gerados pelo sistema. Consultar datas, etapas, eventos e bloqueios em dias não letivos. |
| Quadro de aulas | Duas aulas por dia, de segunda a sexta, em cada turma, vinculadas à professora e às disciplinas. |
| Frequência individual e em lote | 6º A por disciplina; 2º A geral. Aluno 01 falta em todos os dias, aluno 02 alterna faltas e os demais têm presença. Editar e comparar os dois modos. |
| Justificativas | Uma justificativa para o aluno 02 de cada turma no último dia registrado. Consultar, editar e emitir relatório. |
| Avaliações numéricas | Duas avaliações por disciplina no 6º A, notas de 3 a 10 e notas não preenchidas. Conferir pendências, filtros, edição e médias. |
| Dispensas | Aluno 10 dispensado na primeira avaliação de cada disciplina, sem nota nessa avaliação. |
| Recuperação de avaliação | Dois alunos por disciplina, com nota 7. Comparar com a avaliação original. |
| Recuperação de etapa e menor nota | Registros por disciplina com notas 7 e 6, respectivamente. Conferir as regras e os cálculos exibidos. |
| Recuperação final | Criada quando a data da carga pertence à quarta etapa. Conferir nota 8 e filtros do calendário. |
| Notas complementares | Configuração QAP e notas 0,5 para três alunos por disciplina. Conferir impacto na média de etapa. |
| Notas de transferência | Um registro por disciplina para o aluno 11 do 6º A. Abrir e experimentar o lançamento de notas pela interface. |
| Conceitos e lançamento em lote | Quatro alunos do 2º A com conceito B nas duas disciplinas; demais disponíveis para lançamento. |
| Pareceres descritivos | Três alunos por turma e disciplina, com textos fictícios na etapa atual. Editar e consultar. |
| Plano de ensino por disciplina e área | Planos com conteúdo, metodologia, avaliação e referências. Experimentar filtros, edição, cópia e parecer. |
| Plano de aula por disciplina e área | Planos no período da carga, com conteúdos. Experimentar edição, cópia, aprovação e relatórios. |
| Conteúdos trabalhados | Registros por disciplina e área de conhecimento vinculados às turmas. Conferir datas e atividades. |
| Observações | Uma observação vinculada ao aluno 01 de cada turma. Consultar por aluno e emitir relatório. |
| Infrequência e busca ativa | Aluno 01 com faltas consecutivas, acompanhamento e busca ativa em andamento. Conferir histórico de ausências. |
| PEI | Aluno 03 com revisão, planejamento curricular, avaliação periódica e versão publicada. Aluno 04 com rascunho. Experimentar edição, versões, publicação, arquivamento e PDF. |
| Notificações | Aviso QA não lido para professor e gestor. Marcar como lido e conferir o contador. |
| Configuração de avaliações | Configuração geral do ano e tipo de atividade QA. Tabela de conceitos A/B/C/D e tabela personalizada sem arredondamento. |
| Equipamentos | Equipamento fictício cadastrado na escola para experimentar o cadastro. Sem dispositivo físico conectado. |
| Relatórios e exportações | Usar a escola QA, turma, disciplina, etapa e período impressos pela carga. Frequência, notas, observações, justificativas, planos e boletins usam os registros descritos acima. |
| Histórico e auditoria | Os registros passam por `create!` e pelas validações/callbacks dos modelos. Abrir histórico e editar registros para comparar alterações. |

## Fluxos com dependências próprias

Sincronização, cadastro remoto de pessoas, laudos do aluno, importações externas e
envio de notas/faltas exigem uma instância de homologação do i-Educar e credenciais
válidas. A carga não simula uma resposta de sucesso desses serviços nem altera a
configuração de integração existente. Testar esses fluxos somente com o destino
de homologação configurado. Biometria exige dispositivo/cliente próprio; envio de
e-mail e SMS exige os respectivos serviços. Backups, ajustes de manutenção e
exportações devem ser solicitados na interface para experimentar o processamento
real pelo Sidekiq; não são fabricados arquivos ou execuções concluídas.

Configurações globais, identidade visual, dicionário de termos e credenciais
existentes são preservados. A equipe pode experimentar suas telas com o gestor QA.
A carga não pretende validar automaticamente todas as ações da aplicação: ela
fornece os registros de suporte e `qa:verify` verifica integridade e cobertura dos dados.

## Repetição e integridade

`qa:seed` é explícita, não é chamada pelo boot ou pelo `db:seed` normal, e recusa
produção. Toda a criação ocorre numa transação: qualquer erro desfaz a carga.
A unidade `QA Escola Laboratório ANO` identifica o conjunto; se ela já existe,
a repetição preserva os dados e as alterações feitas pelos testadores.
Não excluir essa unidade isoladamente para tentar recriar a carga.

```powershell
docker compose exec -T -e DISABLE_SPRING=1 puma bundle exec rake qa:verify
```

A verificação exige as duas turmas, os 24 alunos e suas enturmações, autenticação
dos dois perfis, registros em todos os módulos verificados, 12 alunos em cada
chamada e notas de recuperação persistidas. Falhas interrompem o comando com erro.

Para conferir login e abertura de páginas do menu com os dois perfis:

```powershell
node script/qa-smoke.js
```

Esse teste HTTP usa o Playwright instalado no projeto, sem abrir navegador.
`QA_BASE_URL`, `QA_YEAR` e `QA_PASSWORD` permitem ajustar o destino e as credenciais.
Ele não substitui a experimentação visual e dos formulários pela equipe.

## Carga local verificada em 18/10/2026

A escola QA tem 2 turmas, 24 alunos e registros de 02 a 16/10/2026:
30 chamadas, 48 registros de notas, 4 avaliações, 4 diários de conceitos,
4 pareceres, 6 planos de ensino, 6 planos de aula, 6 registros de conteúdo,
8 recuperações, 2 notas complementares, 2 registros de transferência,
2 justificativas, 2 observações, 2 acompanhamentos de infrequência,
4 PEIs (2 com versão publicada) e 2 quadros de aulas.

`qa:verify` passou após a carga e após sua repetição, com as mesmas quantidades.
As quatro views materializadas foram atualizadas. O teste HTTP passou para os
dois perfis: login, painel e páginas de consulta selecionadas do menu, incluindo
PEI, planejamentos, diários e formulários de relatórios. A geração dos arquivos de
relatório e a interação visual com os formulários ficam para a equipe de teste.
