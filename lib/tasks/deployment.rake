namespace :deployment do
  desc 'Migra o banco e configura a entidade única para a instalação Render'
  task prepare: :environment do
    abort 'Use RAILS_ENV=production para preparar esta implantação.' unless Rails.env.production?
    host = ENV['APP_HOST'].presence || ENV['RENDER_EXTERNAL_HOSTNAME'].presence
    abort 'Configure APP_HOST ou RENDER_EXTERNAL_HOSTNAME com o domínio, sem https://.' if host.blank?
    abort 'O domínio deve conter apenas o hostname, sem protocolo ou caminho.' if host.include?('/') || host.include?(':')

    ENV['VERBOSE'] ||= 'false'
    Rake::Task['db:migrate'].invoke
    # Modelos carregados durante as migrações podem manter colunas de uma versão antiga da tabela.
    ActiveRecord::Base.connection.schema_cache.clear!
    ActiveRecord::Base.descendants.each(&:reset_column_information)
    $REDIS_DB.ping

    name = ENV.fetch('ENTITY_NAME', 'prefeitura')
    # Esta instalação usa uma única entidade no banco gerenciado informado por DATABASE_URL.
    # Não executa CREATE DATABASE nem exige privilégios administrativos do PostgreSQL.
    entity = Entity.find_or_initialize_by(name: name)
    entity.domain = host
    entity.config = { database: ActiveRecord::Base.connection.current_database } if entity.new_record?
    entity.save!

    needs_admin = entity.using_connection { !User.exists?(login: 'admin') }
    if needs_admin
      password = ENV.fetch('ADMIN_PASSWORD') { abort 'Configure ADMIN_PASSWORD para criar o primeiro administrador.' }
      creator = AdminUserCreator.new('NAME' => name, 'ADMIN_PASSWORD' => password)
      creator.create
      abort creator.status unless entity.using_connection { User.exists?(login: 'admin', admin: true) }
    end
    puts "Implantação preparada para #{host}; administrador existente preservado."
  end
end
