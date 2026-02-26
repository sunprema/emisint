defmodule Emisint.Registry do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Registry.AcademicYear do
      define :create_academic_year, action: :create
      define :get_academic_year, action: :read, get_by: [:id]
      define :list_academic_years, action: :read
      define :update_academic_year, action: :update
    end

    resource Emisint.Registry.Student do
      define :create_student, action: :create
      define :get_student, action: :read, get_by: [:id]
      define :get_student_by_uic, action: :read, get_by: [:uic]
      define :list_students, action: :read
      define :update_student, action: :update
    end

    resource Emisint.Registry.Enrollment do
      define :create_enrollment, action: :create
      define :get_enrollment, action: :read, get_by: [:id]
      define :list_enrollments, action: :read
      define :update_enrollment, action: :update
    end
  end
end
