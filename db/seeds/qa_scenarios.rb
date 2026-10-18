# frozen_string_literal: true

class QaScenarios
  def initialize
    @year = Date.current.year
    @start = Date.new(@year, 1, 1)
    @finish = Date.new(@year, 12, 31)
    @password = ENV.fetch('QA_PASSWORD', 'QaTeste2026!')
  end

  def run
    raise 'Ambiente não permitido' unless Rails.env.development? || Rails.env.test?
    ActiveRecord::Base.transaction do
      # Serializa execuções simultâneas; a unidade identifica o conjunto inteiro.
      ActiveRecord::Base.connection.execute('SELECT pg_advisory_xact_lock(20261018)')
      if Unity.exists?(name: "QA Escola Laboratório #{@year}")
        puts 'Cenários QA já instalados para este ano; registros preservados.'
        return
      end
      @admin = User.find_by!(login: 'admin')
      @unity = Unity.create!(name: "QA Escola Laboratório #{@year}", api_code: code(1),
                             author: @admin, unit_type: UnitTypes::SCHOOL_UNIT)
      @unity.unity_equipments.create!(code: code(900), biometric_type: BiometricTypes::SAGEM)
      @calendar = SchoolCalendar.create!(unity: @unity, year: @year, number_of_classes: 5,
                                        opened_year: true, step_type_description: "QA Bimestre #{@year}")
      4.times do |index|
        @calendar.steps.create!(step_number: index + 1,
          start_at: Date.new(@year, index * 3 + 1, 1),
          end_at: Date.new(@year, index * 3 + 3, 1).end_of_month,
          start_date_for_posting: @start, end_date_for_posting: @finish)
      end
      @dates = [Date.current, @finish].min.downto(@start).lazy.select do |date|
        @calendar.school_day?(date)
      end.take(10).to_a.reverse
      raise 'Sem dias letivos passados para os cenários QA.' if @dates.empty?
      @date = @dates.last
      @step = @calendar.step(@date)
      @term = SchoolTermType.create!(description: "QA Bimestre #{@year} (4 etapas)", steps_number: 4)
      4.times { |i| @term.school_term_type_steps.create!(step_number: i + 1) }
      @setting = TestSetting.find_by(year: @year, exam_setting_type: ExamSettingTypes::GENERAL)
      @setting ||= TestSetting.create!(year: @year, exam_setting_type: ExamSettingTypes::GENERAL,
        minimum_score: 0, maximum_score: 10, number_of_decimal_places: 2,
        average_calculation_type: AverageCalculationTypes::ARITHMETIC)
      @area = KnowledgeArea.create!(description: "QA Linguagens #{@year}", api_code: code(2))
      @disciplines = ['Língua Portuguesa', 'Matemática'].each_with_index.map do |name, index|
        Discipline.create!(description: "QA #{name}", api_code: code(10 + index), knowledge_area: @area)
      end
      @course = Course.create!(description: 'QA Ensino Fundamental', api_code: code(20))
      @teacher = Teacher.create!(name: 'QA Professora Ana Exemplo', api_code: code(30), active: true)
      @teacher_user = create_user('qa.professor', 'Professora', AccessLevel::TEACHER, @teacher)
      @manager = create_user('qa.gestor', 'Gestor', AccessLevel::ADMINISTRATOR)
      @classrooms = []
      @all_students = []
      [false, true].each_with_index { |conceptual, index| create_classroom(conceptual, index) }
      @teacher_user.update!(current_unity_id: @unity.id, current_classroom_id: @classrooms.first.id,
        current_discipline_id: @disciplines.first.id, current_school_year: @year)
      @manager.update!(current_unity_id: @unity.id, current_classroom_id: @classrooms.first.id,
        current_discipline_id: @disciplines.first.id, current_school_year: @year,
        assumed_teacher_id: @teacher.id)
      notification = SystemNotification.create!(title: 'QA Ambiente de experimentação',
        description: 'Dados inteiramente fictícios. Consulte docs/TESTES-QA.md para os cenários.', generic: true)
      [@teacher_user, @manager].each { |user| notification.targets.create!(user: user, read: false) }
      refresh_views
      puts "QA concluído: #{@unity.name}; #{@classrooms.size} turmas; #{@all_students.size} alunos; datas #{@dates.first} a #{@date}."
    end
  end

  private

  def refresh_views
    %w[mvw_frequency_by_school_classroom_teachers mvw_content_record_by_school_classroom_teachers
       mvw_infrequency_tracking_students mvw_infrequency_tracking_classrooms].each do |view|
      ActiveRecord::Base.connection.execute("REFRESH MATERIALIZED VIEW #{view}")
      MaterializedViewRefresh.register!(view)
    end
  end

  def code(number)
    "QA-#{@year}-#{number}"
  end

  def create_user(login, name, access_level, teacher = nil)
    role = Role.create!(name: "QA #{name} #{@year}", access_level: access_level, author: @admin)
    Features.list.each do |feature|
      permission = role.permissions.build(feature: feature, permission: Permissions::CHANGE)
      permission.permission = Permissions::DENIED unless permission.access_level_has_feature?(access_level)
    end
    role.save!
    user = User.create!(login: "#{login}.#{@year}", first_name: 'QA', last_name: name,
      email: "#{login}.#{@year}@example.org", password: @password, password_confirmation: @password,
      teacher: teacher, status: 'active', kind: 'employee', admin: false, receive_news: false)
    user_role = UserRole.create!(user: user, role: role, unity: @unity)
    user.update!(current_user_role: user_role)
    user
  end

  def create_classroom(conceptual, index)
    rule = ExamRule.create!(api_code: code(40 + index),
      score_type: conceptual ? ScoreTypes::CONCEPT : ScoreTypes::NUMERIC,
      frequency_type: conceptual ? FrequencyTypes::GENERAL : FrequencyTypes::BY_DISCIPLINE,
      opinion_type: OpinionTypes::BY_STEP_AND_DISCIPLINE, recovery_type: RecoveryTypes::PARALLEL,
      final_recovery_maximum_score: 10)
    if conceptual
      table = RoundingTable.create!(name: "QA Conceitos #{@year}", api_code: code(42))
      [['A', 10], ['B', 8], ['C', 6], ['D', 4]].each do |label, value|
        table.rounding_table_values.create!(rounding_table_api_code: table.api_code,
          label: label, value: value, action: RoundingTableAction::NONE)
      end
      rule.update!(rounding_table: table)
    end
    grade = Grade.create!(course: @course, description: conceptual ? 'QA 2º ano' : 'QA 6º ano',
                          api_code: code(50 + index))
    classroom = Classroom.create!(unity: @unity, unity_code: @unity.api_code,
      description: conceptual ? 'QA 2º A - Conceitos e frequência geral' : 'QA 6º A - Notas e frequência por disciplina',
      api_code: code(60 + index), year: @year, period: Periods::MATUTINAL)
    @classrooms << classroom
    link = ClassroomsGrade.create!(classroom: classroom, grade: grade, exam_rule: rule)
    @disciplines.each do |discipline|
      TeacherDisciplineClassroom.create!(classroom: classroom, teacher: @teacher, grade: grade,
        discipline: discipline, year: @year, teacher_api_code: @teacher.api_code,
        classroom_api_code: classroom.api_code, discipline_api_code: discipline.api_code,
        allow_absence_by_discipline: conceptual ? 0 : 1, active: true)
      SchoolCalendarDisciplineGrade.create!(school_calendar: @calendar, discipline: discipline, grade: grade)
    end
    students = 12.times.map do |number|
      student = Student.create!(name: format('QA Aluno %02d Turma %d', number + 1, index + 1),
        api_code: code(100 + index * 20 + number), api: true)
      enrollment = StudentEnrollment.create!(student: student, status: 3, active: IeducarBooleanState::ACTIVE)
      StudentEnrollmentClassroom.create!(student_enrollment: enrollment, classrooms_grade: link,
        api_code: code(200 + index * 20 + number), classroom_code: classroom.api_code,
        joined_at: @start, changed_at: @start, show_as_inactive_when_not_in_date: false)
      student
    end
    @all_students.concat(students)
    create_attendance(classroom, students, conceptual)
    @disciplines.each do |discipline|
      create_plans(classroom, grade, discipline)
      conceptual ? create_concepts(classroom, discipline, students) : create_scores(classroom, grade, discipline, students)
      DescriptiveExam.create!(classroom: classroom, discipline: discipline, teacher_id: @teacher.id,
        opinion_type: OpinionTypes::BY_STEP_AND_DISCIPLINE, recorded_at: @date,
        step_id: @step.id, step_number: @step.step_number).tap do |exam|
        students.first(3).each do |student|
          DescriptiveExamStudent.create!(descriptive_exam: exam, student: student,
            value: 'QA: participa das atividades e está desenvolvendo autonomia na aprendizagem.')
        end
      end
    end
    create_area_plans(classroom, grade)
    create_extra_scores(classroom, grade, students) unless conceptual
    create_support(classroom, students)
    board = LessonsBoard.create!(classrooms_grade: link, period: Periods::MATUTINAL)
    2.times do |i|
      lesson = board.lessons_board_lessons.create!(lesson_number: i + 1)
      %w[monday tuesday wednesday thursday friday].each do |day|
        allocation = TeacherDisciplineClassroom.find_by!(classroom: classroom,
          teacher: @teacher, discipline: @disciplines[i])
        lesson.lessons_board_lesson_weekdays.create!(weekday: day, teacher_discipline_classroom: allocation)
      end
    end
  end

  def create_attendance(classroom, students, general)
    @dates.each_with_index do |date, day|
      (general ? [nil] : @disciplines).each do |discipline|
        DailyFrequency.create!(unity: @unity, classroom: classroom, school_calendar: @calendar,
          discipline: discipline, teacher: @teacher, frequency_date: date,
          class_number: general ? nil : 1, period: Periods::MATUTINAL,
          students_attributes: students.each_with_index.map { |student, i|
            { student_id: student.id, active: true, present: !(i.zero? || (i == 1 && day.even?)) }
          })
      end
    end
  end

  def create_scores(classroom, grade, discipline, students)
    [@dates.first, @date].uniq.each_with_index do |date, index|
      test = @setting.tests.create!(description: "QA Atividade #{index + 1} - #{discipline.description}",
        weight: 10, allow_break_up: false)
      exam = Avaliation.create!(classroom: classroom, discipline: discipline,
        school_calendar: @calendar, test_setting: @setting, test_setting_test: test,
        teacher_id: @teacher.id, test_date: date, classes: '1', weight: 10,
        description: "QA Avaliação #{index + 1}", grade_ids: [grade.id])
      note = DailyNote.create!(avaliation: exam)
      students.each_with_index do |student, i|
        DailyNoteStudent.create!(daily_note: note, student: student, active: true,
          note: [9, 11].include?(i) ? nil : [3, 5, 7, 8.5, 10][i % 5])
      end
      AvaliationExemption.create!(avaliation: exam, student: students[9], teacher_id: @teacher.id,
        reason: 'QA Dispensa fictícia') if index.zero?
      next unless index.zero?
      recovery = RecoveryDiaryRecord.new(unity: @unity, classroom: classroom, discipline: discipline,
        teacher_id: @teacher.id, current_user: @teacher_user, recorded_at: @date,
        students_attributes: students.first(2).map { |student| { student_id: student.id, score: 7 } })
      AvaliationRecoveryDiaryRecord.create!(avaliation: exam, recovery_diary_record: recovery)
    end
  end

  def create_concepts(classroom, discipline, students)
    students.first(4).each do |student|
      exam = ConceptualExam.find_or_initialize_by(classroom: classroom, student: student,
        step_number: @step.step_number)
      exam.assign_attributes(unity_id: @unity.id, teacher_id: @teacher.id, current_user: @teacher_user,
        recorded_at: @date, step_id: @step.id)
      exam.conceptual_exam_values.build(discipline: discipline, value: 'B')
      exam.save!
    end
  end

  def create_plans(classroom, grade, discipline)
    content = Content.find_or_create_by!(description: "QA Leitura e resolução de problemas - #{discipline.description}")
    objective = Objective.find_or_create_by!(description: 'QA Desenvolver interpretação e autonomia')
    teaching = TeachingPlan.new(unity: @unity, grade: grade, teacher: @teacher, year: @year,
      school_term_type: @term, school_term_type_step: @term.school_term_type_steps.find_by!(step_number: @step.step_number),
      methodology: 'QA Rodas de conversa e atividades em grupo', evaluation: 'QA Observação e atividade prática',
      references: 'QA Material didático fictício', contents: [content], objectives: [objective],
      contents_created_at_position: { content.id => 0 }, objectives_created_at_position: { objective.id => 0 })
    DisciplineTeachingPlan.create!(teaching_plan: teaching, discipline: discipline, teacher_id: @teacher.id)
    lesson = LessonPlan.new(classroom: classroom, school_calendar: @calendar, teacher: @teacher,
      start_at: @dates.first, end_at: @date, contents: [content], objectives: [objective],
      contents_created_at_position: { content.id => 0 }, objectives_created_at_position: { objective.id => 0 })
    DisciplineLessonPlan.create!(lesson_plan: lesson, discipline: discipline, teacher_id: @teacher.id)
    record = ContentRecord.new(classroom: classroom, teacher: @teacher, record_date: @date,
      contents: [content], daily_activities_record: 'QA Leitura compartilhada e exercícios de fixação')
    DisciplineContentRecord.create!(content_record: record, discipline: discipline, teacher_id: @teacher.id)
  end

  def create_support(classroom, students)
    AbsenceJustification.create!(unity: @unity, classroom: classroom, school_calendar: @calendar,
      teacher: @teacher, user: @teacher_user, absence_date: @date, absence_date_end: @date,
      justification: 'QA Compromisso familiar fictício', students: [students[1]], disciplines: @disciplines,
      period: Periods::MATUTINAL)
    observation = ObservationDiaryRecord.new(classroom: classroom, discipline: @disciplines.first,
      teacher: @teacher, school_calendar: @calendar, date: @date)
    observation.notes.build(description: 'QA Necessita de apoio na organização das atividades', students: [students.first])
    observation.save!
    enrollment = StudentEnrollment.find_by!(student: students.first)
    ActiveSearch.create!(student_enrollment: enrollment, start_date: @date,
      status: ActiveSearchStatus::IN_PROGRESS, observations: 'QA Contato fictício com responsáveis',
      api_code: code(500 + classroom.id))
    InfrequencyTracking.create!(student: students.first, classroom: classroom, notification_date: @date,
      notification_type: InfrequencyTrackingTypes::CONSECUTIVE_ABSENCES,
      notification_data: [{ teacher_id: @teacher.id, absences: @dates.map(&:to_s) }])
    plan = IndividualizedEducationalPlan.create!(student: students[2], year: @year,
      elaborated_at: @date, aee_teacher: @teacher)
    review = plan.iep_review_dates.create!(review_date: @date)
    plan.iep_curricular_plannings.create!(iep_review_date: review, discipline: @disciplines.first,
      long_term_goal: 'QA Desenvolver leitura autônoma', stage_objectives: 'QA Interpretar textos curtos',
      skills_to_develop: 'QA Identificar ideias principais', methodologies: 'QA Apoio visual e leitura guiada')
    plan.iep_periodic_evaluations.create!(iep_review_date: review, discipline: @disciplines.first,
      acquired_skills: 'QA Reconhece palavras frequentes', in_progress_skills: 'QA Leitura de frases',
      period_report: 'QA Participa com apoio visual', next_stage_adjustments: 'QA Ampliar tempo de leitura')
    IndividualizedEducationalPlanPublisher.publish!(plan, name: 'QA Versão inicial',
      published_by: @teacher_user, classroom: classroom,
      student_data: { guardians: 'QA Responsável Exemplo', guardians_unavailable: false, shift: 'Matutino' })
    IndividualizedEducationalPlan.create!(student: students[3], year: @year,
      elaborated_at: @date, aee_teacher: @teacher)
  end

  def create_area_plans(classroom, grade)
    content = Content.find_or_create_by!(description: 'QA Projeto interdisciplinar de leitura')
    teaching = TeachingPlan.new(unity: @unity, grade: grade, teacher: @teacher, year: @year,
      school_term_type: @term, school_term_type_step: @term.school_term_type_steps.find_by!(step_number: @step.step_number),
      methodology: 'QA Projeto em grupo', evaluation: 'QA Portfólio', references: 'QA Biblioteca fictícia',
      contents: [content], contents_created_at_position: { content.id => 0 })
    KnowledgeAreaTeachingPlan.create!(teaching_plan: teaching, knowledge_areas: [@area], teacher_id: @teacher.id)
    lesson = LessonPlan.new(classroom: classroom, school_calendar: @calendar, teacher: @teacher,
      start_at: @dates.first, end_at: @date, contents: [content], contents_created_at_position: { content.id => 0 })
    KnowledgeAreaLessonPlan.create!(lesson_plan: lesson, knowledge_areas: [@area], teacher_id: @teacher.id)
    record = ContentRecord.new(classroom: classroom, teacher: @teacher, record_date: @dates.first,
      contents: [content], daily_activities_record: 'QA Projeto interdisciplinar desenvolvido em grupo')
    KnowledgeAreaContentRecord.create!(content_record: record, knowledge_areas: [@area], teacher_id: @teacher.id)
  end

  def create_extra_scores(classroom, grade, students)
    CustomRoundingTable.create!(name: "QA Arredondamento #{@year}", year: @year,
      unities: [@unity], courses: [@course], grades: [grade],
      rounded_avaliations: ['numerical_exam', 'school_term_recovery', 'final_recovery'],
      custom_rounding_table_values_attributes: 10.times.map { |i| { label: i.to_s, action: 0 } })
    setting = ComplementaryExamSetting.create!(description: "QA Participação #{@year}", initials: 'QAP',
      affected_score: AffectedScoreTypes::STEP_AVERAGE, calculation_type: CalculationTypes::SUM,
      maximum_score: 1, number_of_decimal_places: 2, year: @year, grades: [grade])
    @disciplines.each do |discipline|
      ComplementaryExam.create!(unity: @unity, classroom: classroom, discipline: discipline,
        complementary_exam_setting: setting, teacher_id: @teacher.id, recorded_at: @date,
        step_id: @step.id, step_number: @step.step_number,
        students_attributes: students.first(3).map { |student| { student_id: student.id, score: 0.5, active: true } })
      recovery = RecoveryDiaryRecord.new(unity: @unity, classroom: classroom, discipline: discipline,
        teacher_id: @teacher.id, current_user: @teacher_user, recorded_at: @date,
        students_attributes: students.first(2).map { |student| { student_id: student.id, score: 7 } })
      SchoolTermRecoveryDiaryRecord.create!(recovery_diary_record: recovery, recorded_at: @date,
        step_id: @step.id, step_number: @step.step_number)
      lowest = RecoveryDiaryRecord.new(unity: @unity, classroom: classroom, discipline: discipline,
        teacher_id: @teacher.id, current_user: @teacher_user, recorded_at: @date,
        students_attributes: [{ student_id: students[1].id, score: 6 }])
      AvaliationRecoveryLowestNote.create!(recovery_diary_record: lowest, recorded_at: @date,
        step_id: @step.id, step_number: @step.step_number)
      if @step.step_number == 4
        final = RecoveryDiaryRecord.new(unity: @unity, classroom: classroom, discipline: discipline,
          teacher_id: @teacher.id, current_user: @teacher_user, recorded_at: @date,
          students_attributes: [{ student_id: students[1].id, score: 8 }])
        FinalRecoveryDiaryRecord.create!(recovery_diary_record: final, school_calendar: @calendar)
      end
      TransferNote.create!(classroom: classroom, discipline: discipline, student: students[10],
        teacher: @teacher, unity_id: @unity.id, recorded_at: @date, transfer_date: @date,
        step_id: @step.id, step_number: @step.step_number)
    end
  end
end
