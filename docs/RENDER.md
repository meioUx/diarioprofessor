# Implantação no Render

A imagem padrão do `Dockerfile` contém a aplicação, dependências e assets de
produção e executa `bash script/render-start`. O Compose local usa o alvo `base`
para manter o ambiente de desenvolvimento com os volumes existentes.

## Serviços e variáveis

Crie um PostgreSQL, um Key Value e um Web Service na mesma região. No Web Service,
conecte `meioUx/diarioprofessor`, branch `main`, linguagem Docker, caminho
`./Dockerfile`. Deixe **Docker Command vazio** para usar o comando da imagem.
Configure o health check como `/up`.

Cadastre em **Environment**:

| Variável | Valor |
| --- | --- |
| `DATABASE_URL` | Internal Database URL do PostgreSQL. |
| `REDIS_URL` | Internal URL do Key Value, com acesso pela rede privada. |
| `SECRET_KEY_BASE` | Segredo longo, aleatório e estável entre deploys. |
| `ADMIN_PASSWORD` | Senha forte para criar o usuário `admin` na primeira inicialização. |
| `APP_HOST` | Opcional: domínio personalizado, sem protocolo ou caminho. Sem ela, usa `RENDER_EXTERNAL_HOSTNAME`. |
| `SIDEKIQ_PASSWORD` | Opcional: senha do painel Sidekiq. Sem ela, usa o segredo da aplicação. |

O ambiente da imagem já define `RAILS_ENV=production`, `RAILS_SERVE_STATIC_FILES=1`
e `RAILS_LOG_TO_STDOUT=1`. Não definir `RAILS_MASTER_KEY`: esta aplicação Rails 5
usa o template `config/secrets.render.yml`, que lê variáveis de ambiente.
Não colocar URLs com senha, senhas ou arquivos `.env` no GitHub.

Para gerar um segredo no computador:

```powershell
docker compose exec -T puma ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
```

Copie o resultado para `SECRET_KEY_BASE` no painel do Render, mantendo o mesmo valor
nos serviços web e worker. Essa geração local não grava segredo no repositório.

## Inicialização

O script valida as variáveis, executa migrações, verifica a conexão com Redis,
cadastra a entidade e cria o administrador se ele não existir. O servidor inicia
em `0.0.0.0` na porta `PORT` fornecida pelo Render (ou 10000).

Esta instalação inicial usa uma única entidade no banco informado por
`DATABASE_URL`, sem criar bancos adicionais. Entidades existentes mantêm a
configuração de conexão. O login inicial é `admin`, com a senha definida em
`ADMIN_PASSWORD`; repetir a preparação não redefine a senha existente.

Para refazer o build, use **Manual Deploy → Clear build cache & deploy**.
O término do build deve ser seguido dos logs de migração/preparação e do Puma,
em vez de `Switch to inspect mode`. Erros de variáveis ausentes são mostrados
explicitamente no log.

Em instalações com migrações executadas separadamente, o comando é
`bundle exec rake deployment:prepare`; defina `RUN_MIGRATIONS=0` no web somente
depois de preparar o banco. Não desligar migrações na primeira inicialização.

## Tarefas em segundo plano e arquivos

Para os processos assíncronos, crie um Background Worker com o mesmo repositório,
Dockerfile e variáveis de conexão/segredos. O comando pode usar:

```sh
bash script/render-start bundle exec sidekiq -c 5 -q critical -q default -q low -q send_emails -q exam_posting -q synchronizer -q synchronizer_full -q synchronizer_enqueue_next_job -q synchronizer_enqueue_next_job_full
```

O modo worker não executa a preparação do banco; publique o web primeiro.
O processamento de sincronização deve respeitar os limites e a concorrência
exigidos pela instância de homologação do i-Educar. Para separar os processadores,
use workers dedicados para as filas de sincronização, com concorrência 1,
como na configuração Docker Compose do projeto.

Uploads locais ficam em `/app/public/uploads`: use armazenamento persistente
para preservá-los entre deploys. Para web e workers compartilharem arquivos,
configure S3 com `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` e
`AWS_BUCKET`. E-mails exigem as variáveis SMTP do template de secrets.

O banco do computador e os dados QA não são enviados no Git push. A tarefa
`qa:seed` mantém o bloqueio de produção; não desative essa proteção para
popular o serviço público. A preparação cria o acesso administrativo, e os
cadastros escolares podem ser sincronizados com o i-Educar configurado para
o ambiente de destino.

Referências: [Docker](https://render.com/docs/docker),
[Web Services](https://render.com/docs/web-services),
[PostgreSQL](https://render.com/docs/postgresql-creating-connecting),
[Sidekiq](https://render.com/docs/deploy-rails-sidekiq).

## Validação local

O teste de produção compilou os assets Rails e Webpack, aplicou 901 migrações
num banco vazio com usuário sem `SUPERUSER` e sem `CREATEDB`, criou uma entidade
e um administrador e iniciou o Puma. Health check, login, painel e os cinco
assets referenciados pelo login responderam HTTP 200. A repetição da preparação
preservou o administrador, sua senha e a configuração da entidade. O worker
também iniciou em produção com uma fila vazia de teste e Redis isolado.
Esses testes locais não configuram nem publicam serviços na conta do Render.
