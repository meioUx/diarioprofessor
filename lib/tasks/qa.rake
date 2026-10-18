namespace :qa do
  desc 'Popula a entidade local com cenários fictícios para homologação'
  task seed: :environment do
    abort 'Carga QA permitida apenas em development/test.' unless Rails.env.development? || Rails.env.test?
    entity = Entity.find_by!(name: ENV.fetch('NAME', 'prefeitura'))
    entity.using_connection do
      require Rails.root.join('db/seeds/qa_scenarios').to_s
      QaScenarios.new.run
    end
  end

  desc 'Verifica os vínculos e a cobertura dos cenários QA instalados'
  task verify: :environment do
    abort 'Verificação QA permitida apenas em development/test.' unless Rails.env.development? || Rails.env.test?
    entity = Entity.find_by!(name: ENV.fetch('NAME', 'prefeitura'))
    entity.using_connection do
      require Rails.root.join('db/seeds/qa_verify').to_s
      QaVerify.run
    end
  end
end
