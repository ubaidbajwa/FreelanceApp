namespace FreelanceApp.Application.Common.Security;

/// <summary>
/// Disposable/temporary email domains ki blocklist.
/// Abhi static list hai — future mein config ya DB se load karna ho to
/// sirf <see cref="IsDisposable"/> ke through hi access hota hai, is liye
/// backing store change karna easy rahega (validators ko touch nahi karna padega).
/// </summary>
public static class DisposableEmailDomains
{
    // Lowercase domains only — comparison case-insensitive hai via OrdinalIgnoreCase
    private static readonly HashSet<string> Domains = new(StringComparer.OrdinalIgnoreCase)
    {
        // 10 Minute Mail family
        "10minutemail.com",
        "10minutemail.net",
        "10minemail.com",
        "10mail.org",
        "20minutemail.com",
        "minuteinbox.com",

        // Temp Mail family
        "temp-mail.org",
        "temp-mail.io",
        "tempmail.com",
        "tempmail.net",
        "tempmail.dev",
        "tempmailo.com",
        "tempail.com",
        "tempr.email",
        "tmpmail.org",
        "tmpmail.net",
        "tmpeml.com",
        "mail-temp.com",
        "mytemp.email",

        // Guerrilla Mail family
        "guerrillamail.com",
        "guerrillamail.net",
        "guerrillamail.org",
        "guerrillamail.biz",
        "guerrillamail.de",
        "guerrillamailblock.com",
        "grr.la",
        "sharklasers.com",
        "pokemail.net",
        "spam4.me",

        // Mailinator family
        "mailinator.com",
        "mailinator.net",
        "mailinator.org",
        "mailinator2.com",

        // Yopmail family
        "yopmail.com",
        "yopmail.fr",
        "yopmail.net",
        "cool.fr.nf",
        "jetable.fr.nf",
        "courriel.fr.nf",
        "moncourrier.fr.nf",

        // Trash / throwaway services
        "trashmail.com",
        "trashmail.de",
        "trash-mail.com",
        "throwawaymail.com",
        "throwam.com",
        "wegwerfmail.de",
        "wegwerfmail.net",
        "kurzepost.de",
        "jetable.org",
        "dispostable.com",
        "discard.email",
        "discardmail.com",

        // Inbox services (no signup, public inboxes)
        "maildrop.cc",
        "mailnesia.com",
        "mailcatch.com",
        "mailsac.com",
        "getnada.com",
        "nada.email",
        "inboxkitten.com",
        "fakeinbox.com",
        "spambox.us",
        "mohmal.com",
        "moakt.com",
        "moakt.cc",
        "dropmail.me",
        "emltmp.com",
        "harakirimail.com",
        "mintemail.com",
        "mailexpire.com",
        "meltmail.com",
        "anonymbox.com",
        "spamgourmet.com",
        "mailnull.com",
        "spamdecoy.net",
        "emailondeck.com",
        "burnermail.io",
        "mail7.io",
        "33mail.com",
        "mailslurp.com",
        "tempinbox.com",
        "incognitomail.com",
        "getairmail.com",
        "fakemailgenerator.com",
        "crazymailing.com",
        "mailondeck.com",
        "tmails.net",
        "disbox.net",
        "luxusmail.org",
        "vomoto.com",
        "zetmail.com",
        "tafmail.com",
        "eyepaste.com",
        "mailhazard.com",
        "binkmail.com",
        "safetymail.info",
        "spamherelots.com",
        "spamhereplease.com",
        "suremail.info",
        "thisisnotmyrealemail.com",
        "tradermail.info",
        "veryrealemail.com",
        "zippymail.info",
    };

    /// <summary>
    /// Email ka domain blocklist mein hai ya nahi.
    /// Invalid/malformed email pe false return karta hai — format validation
    /// EmailAddress() rule ka kaam hai, is method ka nahi.
    /// </summary>
    public static bool IsDisposable(string? email)
    {
        if (string.IsNullOrWhiteSpace(email))
            return false;

        var atIndex = email.LastIndexOf('@');
        if (atIndex < 0 || atIndex == email.Length - 1)
            return false;

        var domain = email[(atIndex + 1)..].Trim();
        return Domains.Contains(domain);
    }
}
