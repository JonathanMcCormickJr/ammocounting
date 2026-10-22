# Settings always apply to the signed-in user; there is no way to address
# another user's settings.
class SettingsController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    if Current.user.update(settings_params)
      redirect_to root_path, notice: "Settings saved."
    else
      redirect_to root_path, alert: "Invalid cost basis method."
    end
  end

  private

  def settings_params
    params.expect(user: [ :cost_basis_method ])
  end
end
