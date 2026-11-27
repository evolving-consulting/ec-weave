@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList')
public class WeaveScheduledSendPayload {
    public Id templateId { get; set; }
    public String recordId { get; set; }
    public String subject { get; set; }
    public String htmlBody { get; set; }
    public List<String> toAddresses { get; set; }
    public List<String> ccAddresses { get; set; }
    public List<String> bccAddresses { get; set; }
    public List<String> attachmentVersionIds { get; set; }
    public String orgWideEmailAddressId { get; set; }
    public Boolean storeHistory { get; set; }
    public String scheduledByUserId { get; set; }
}
