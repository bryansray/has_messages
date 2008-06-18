# Represents a recipient on a message.  The kind of recipient (to, cc, or bcc) is
# determined by the +kind+ attribute.
# 
# == States
#
# Recipients can be in 1 of 2 states:
# * +unread+ - The message has been sent, but not yet read by the recipient.  This is the *initial* state.
# * +read+ - The message has been read by the recipient
# 
# == Interacting with the message
# 
# In order to perform actions on the message, such as viewing, you should always
# use the associated event action:
# * +view!+ - Marks the message as read by the recipient
# 
# == Hiding messages
# 
# Although you can delete a recipient, it will also delete it from everyone else's
# message, meaning that no one will know that person was ever a recipient of the
# message.  Instead, you can hide messages from users with the following actions:
# * +hide!+ -Hides the message from the recipient's inbox
# * +unhide!+ - Makes the message visible again
class MessageRecipient < ActiveRecord::Base
  belongs_to  :message
  belongs_to  :receiver, :polymorphic => true
  
  validates_presence_of :message_id,
                        :kind,
                        :receiver_id,
                        :receiver_type
  
  before_create :set_position
  before_destroy :reorder_positions
  
  # Make this class look like the actual message
  delegate  :sender, :subject, :body, :recipients, :to, :cc, :bcc, :created_at,
            :to => :message
  
  named_scope :visible, :conditions => {:hidden_at => nil}
  
  acts_as_state_machine :initial => :unread
  
  state :unread
  state :read
  
  event :view do
    transitions :from => :unread, :to => :read, :guard => :message_sent?
  end

  # Forwards the message
  def forward
    message = self.message.class.new(:subject => subject, :body => body)
    message.sender = receiver
    message
  end
  
  # Replies to the message
  def reply
    message = self.message.class.new(:subject => subject, :body => body)
    message.sender = receiver
    message.to(sender)
    message
  end
  
  # Replies to all recipients on the message, including the original sender
  def reply_to_all
    message = reply
    message.to(to - [receiver] + [sender])
    message.cc(cc - [receiver])
    message.bcc(bcc - [receiver])
    message
  end
  
  # Hides the message from the recipient's inbox
  def hide!
    update_attribute(:hidden_at, Time.now)
  end
  
  # Makes the message visible in the recipient's inbox
  def unhide!
    update_attribute(:hidden_at, nil)
  end
  
  # Is this message still hidden from the recipient's inbox?
  def hidden?
    hidden_at?
  end
  
  private
    # Has the message this recipient is on been sent?
    def message_sent?
      message.state == 'sent'
    end
    
    # Sets the position of the current recipient based on existing recipients
    def set_position
      if last_recipient = message.recipients.find(:first, :conditions => {:kind => kind}, :order => 'position DESC')
        self.position = last_recipient.position + 1
      else
        self.position = 1
      end
    end
    
    # Reorders the positions of the message's recipients
    def reorder_positions
      if position
        position = self.position
        update_attribute(:position, nil)
        self.class.update_all('position = (position - 1)', ['message_id = ? AND kind = ? AND position > ?', message_id, kind, position])
      end
    end
end
