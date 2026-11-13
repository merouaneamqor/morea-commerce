require "rails_helper"

RSpec.describe User, "confirmation agents" do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "agent-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }

  def staff(role:, admin: true, workspace: store)
    workspace.users.create!(email: "#{role}-#{SecureRandom.hex(5)}@example.test", password: password,
      admin: admin, confirmation_role: role)
  end

  it "stores an agent as a non-admin even when the admin flag was submitted" do
    agent = staff(role: "agent", admin: true)

    expect(agent.reload.admin).to be(false)
    expect(agent.confirmation_agent?).to be(true)
  end

  it "keeps supervisors as admins" do
    expect(staff(role: "supervisor", admin: true).reload.admin).to be(true)
  end

  it "refuses an agent who is an admin at the database level" do
    agent = staff(role: "agent")

    expect { agent.update_column(:admin, true) }.to raise_error(ActiveRecord::StatementInvalid, /users_agent_not_admin/)
  end

  it "lets agents sign in and work only their own store's desk" do
    agent = staff(role: "agent")
    other = Store.create!(slug: "other-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")

    expect(agent.can_sign_in?).to be(true)
    expect(agent.can_work_desk_for?(store.id)).to be(true)
    expect(agent.can_work_desk_for?(other.id)).to be(false)
  end
end
