# frozen_string_literal: true

class QaVerify
  def self.run
    year = Date.current.year
    unity = Unity.find_by!(name: "QA Escola Laboratório #{year}")
    classrooms = Classroom.where(unity: unity)
    students = Student.where('api_code LIKE ?', "QA-#{year}-%")
    raise 'Turmas incompletas' unless classrooms.count == 2
    raise 'Alunos incompletos' unless students.count == 24
    raise 'Matrículas incompletas' unless StudentEnrollmentClassroom.where(classrooms_grade_id:
      ClassroomsGrade.where(classroom: classrooms).select(:id)).count == 24
    %w[professor gestor].each do |kind|
      user = User.find_by!(login: "qa.#{kind}.#{year}")
      raise 'Acesso incompleto' unless user.current_user_role && user.current_unity_id == unity.id
      raise 'Senha inválida' unless user.valid_password?(ENV.fetch('QA_PASSWORD', 'QaTeste2026!'))
    end
    counts = {
      turmas: classrooms.count, alunos: students.count,
      frequencias: DailyFrequency.where(classroom: classrooms).count,
      avaliacoes: Avaliation.where(classroom: classrooms).count,
      notas: DailyNoteStudent.joins(:daily_note).where(daily_notes: {
        avaliation_id: Avaliation.where(classroom: classrooms).select(:id) }).count,
      conceitos: ConceptualExam.where(classroom: classrooms).count,
      pareceres: DescriptiveExam.where(classroom: classrooms).count,
      planos_ensino: TeachingPlan.where(unity: unity).count,
      planos_aula: LessonPlan.where(classroom: classrooms).count,
      conteudos: ContentRecord.where(classroom: classrooms).count,
      recuperacoes: RecoveryDiaryRecord.where(classroom: classrooms).count,
      notas_complementares: ComplementaryExam.where(classroom: classrooms).count,
      transferencias: TransferNote.where(classroom: classrooms).count,
      justificativas: AbsenceJustification.where(classroom: classrooms).count,
      observacoes: ObservationDiaryRecord.where(classroom: classrooms).count,
      infrequencia: InfrequencyTracking.where(classroom: classrooms).count,
      pei: IndividualizedEducationalPlan.where(student: students).count,
      versoes_pei: IepVersion.where(classroom: classrooms).count,
      quadros_aula: LessonsBoard.where(classrooms_grade_id:
        ClassroomsGrade.where(classroom: classrooms).select(:id)).count
    }
    raise "Módulo sem dados: #{counts.inspect}" if counts.values.any?(&:zero?)
    frequencies = DailyFrequency.where(classroom: classrooms)
    raise 'Frequência sem alunos' if frequencies.any? { |frequency| frequency.students.count != 12 }
    raise 'Notas de recuperação não persistidas' if RecoveryDiaryRecordStudent.where(
      recovery_diary_record_id: RecoveryDiaryRecord.where(classroom: classrooms).select(:id), score: nil).exists?
    puts JSON.pretty_generate(counts)
    puts "Período QA: #{frequencies.minimum(:frequency_date)} a #{frequencies.maximum(:frequency_date)}"
  end
end
