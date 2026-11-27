public with sharing class WeavePacketController {

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class PacketDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String titleTemplate { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public List<PacketItemDTO> items { get; set; }
        @AuraEnabled public List<Id> deletedItemIds { get; set; }

        public PacketDTO() {
            this.status = 'Draft';
            this.items = new List<PacketItemDTO>();
            this.deletedItemIds = new List<Id>();
        }
    }

    public class PacketItemDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public Id templateId { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public String recordSource { get; set; }
        @AuraEnabled public String staticRecordId { get; set; }
        @AuraEnabled public String parentLookupField { get; set; }

        public PacketItemDTO() { this.recordSource = 'Source Record'; }
    }

    public class PacketSummaryDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String titleTemplate { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Integer itemCount { get; set; }
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<PacketSummaryDTO> getPackets() {
        List<Weave_Document_Packet__c> rows = [
            SELECT Id, Name, Status__c, Title_Template__c, Description__c,
                (SELECT Id FROM Packet_Items__r)
            FROM Weave_Document_Packet__c
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
        List<PacketSummaryDTO> result = new List<PacketSummaryDTO>();
        for (Weave_Document_Packet__c r : rows) {
            PacketSummaryDTO dto = new PacketSummaryDTO();
            dto.id            = r.Id;
            dto.name          = r.Name;
            dto.status        = r.Status__c;
            dto.titleTemplate = r.Title_Template__c;
            dto.description   = r.Description__c;
            dto.itemCount     = r.Packet_Items__r.size();
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static PacketDTO loadPacket(Id packetId) {
        if (packetId == null) return null;
        List<Weave_Document_Packet__c> rows = [
            SELECT Id, Name, Status__c, Title_Template__c, Description__c,
                (SELECT Id, Template__c, Template__r.Name, Display_Order__c,
                        Record_Source__c, Static_Record_Id__c, Parent_Lookup_Field__c
                 FROM Packet_Items__r ORDER BY Display_Order__c ASC NULLS LAST)
            FROM Weave_Document_Packet__c
            WHERE Id = :packetId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        Weave_Document_Packet__c r = rows[0];

        PacketDTO dto = new PacketDTO();
        dto.id            = r.Id;
        dto.name          = r.Name;
        dto.status        = r.Status__c;
        dto.titleTemplate = r.Title_Template__c;
        dto.description   = r.Description__c;
        for (Weave_Packet_Item__c item : r.Packet_Items__r) {
            PacketItemDTO i = new PacketItemDTO();
            i.id                = item.Id;
            i.templateId        = item.Template__c;
            i.templateName      = item.Template__r?.Name;
            i.displayOrder      = item.Display_Order__c != null ? item.Display_Order__c.intValue() : 0;
            i.recordSource      = item.Record_Source__c;
            i.staticRecordId    = item.Static_Record_Id__c;
            i.parentLookupField = item.Parent_Lookup_Field__c;
            dto.items.add(i);
        }
        return dto;
    }

    // ── Mutations ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Id savePacket(String packetJson) {
        PacketDTO dto;
        try { dto = (PacketDTO) JSON.deserialize(packetJson, PacketDTO.class); }
        catch (Exception e) { throw new AuraHandledException('Invalid packet data: ' + e.getMessage()); }

        if (String.isBlank(dto.name)) throw new AuraHandledException('Packet name is required.');

        Weave_Document_Packet__c rec = dto.id != null
            ? new Weave_Document_Packet__c(Id = dto.id)
            : new Weave_Document_Packet__c();
        rec.Name               = dto.name;
        rec.Status__c          = String.isBlank(dto.status) ? 'Draft' : dto.status;
        rec.Title_Template__c  = dto.titleTemplate;
        rec.Description__c     = dto.description;
        upsert as user rec;

        if (dto.deletedItemIds != null && !dto.deletedItemIds.isEmpty()) {
            List<Weave_Packet_Item__c> toDelete = [
                SELECT Id FROM Weave_Packet_Item__c
                WHERE Id IN :dto.deletedItemIds AND Weave_Document_Packet__c = :rec.Id
                WITH USER_MODE
            ];
            delete as user toDelete;
        }

        if (dto.items != null && !dto.items.isEmpty()) {
            List<Weave_Packet_Item__c> toUpsert = new List<Weave_Packet_Item__c>();
            Integer order = 0;
            for (PacketItemDTO i : dto.items) {
                if (i.templateId == null) continue;
                Weave_Packet_Item__c item = i.id != null
                    ? new Weave_Packet_Item__c(Id = i.id)
                    : new Weave_Packet_Item__c(Weave_Document_Packet__c = rec.Id);
                item.Template__c         = i.templateId;
                item.Display_Order__c    = i.displayOrder != null ? i.displayOrder : order;
                item.Record_Source__c    = String.isBlank(i.recordSource) ? 'Source Record' : i.recordSource;
                item.Static_Record_Id__c = i.staticRecordId;
                item.Parent_Lookup_Field__c = i.parentLookupField;
                toUpsert.add(item);
                order++;
            }
            upsert as user toUpsert;
        }

        return rec.Id;
    }

    @AuraEnabled
    public static void deletePacket(Id packetId) {
        if (packetId == null) throw new AuraHandledException('Packet Id is required.');
        List<Weave_Document_Packet__c> rows = [
            SELECT Id FROM Weave_Document_Packet__c WHERE Id = :packetId WITH USER_MODE LIMIT 1
        ];
        if (!rows.isEmpty()) delete as user rows;
    }

    // ── Generation ────────────────────────────────────────────────────────────

    @AuraEnabled
    public static String generatePacket(Id packetId, Id sourceRecordId) {
        try {
            ContentVersion cv = WeavePdfService.generatePacketPdf(packetId, sourceRecordId);
            return cv.ContentDocumentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
