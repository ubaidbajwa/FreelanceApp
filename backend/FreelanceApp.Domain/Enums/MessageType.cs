namespace FreelanceApp.Domain.Enums;

// Sirf Text M1 mein use hota hai. Baaki values abhi define kar diye taake baad ke
// slices additive rahein — naya enum member add karne pe migration churn na ho.
public enum MessageType
{
    Text   = 0,
    Image  = 1,
    File   = 2,
    Voice  = 3,
    System = 4   // Inline activity marker (pin/unpin). Body is always empty; client renders from SystemEventType.
}
