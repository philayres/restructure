# frozen_string_literal: true

Rails.application.config.to_prepare do
  # Set up the Users::Reminders configurations by setting the class attributes
  Users::Reminders.password_expiration_defaults = {
    content: 'server password expiration reminder',
    layout: 'server password expiration reminder',
    subject: 'Password Expiration Reminder',
    remind_after: (Settings::PasswordAgeLimit - Settings::PasswordReminderDays).days,
    repeat_reminder_every: Settings::PasswordReminderRepeatDays.days
  }

  # TODO: should I move to a more specifically named initializer?
  # Set up the Users::Confirmations notifications by setting the class attributes
  Users::Confirmations.confirmation_defaults = {
    content: 'server registration confirmation',
    layout: 'server registration confirmation',
    subject: 'Registration Confirmation Notification'
  }

  # TODO: should I move to a more specifically named initializer?
  # Set up the Users::PasswordRecovery notifications by setting the class attributes
  Users::PasswordRecovery.password_recovery_defaults = {
    content: 'server reset password instructions',
    layout: 'server reset password instructions',
    subject: 'Reset Password Instructions'
  }
end
