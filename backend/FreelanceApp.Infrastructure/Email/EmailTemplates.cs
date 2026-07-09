namespace FreelanceApp.Infrastructure.Email;

public static class EmailTemplates
{
    public static string EmailVerificationOtp(string userName, string otpCode, int expiryMinutes)
    {
        return $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <style>
        body {{ font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; }}
        .container {{ max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; }}
        .header {{ background-color: #2563eb; color: #ffffff; padding: 30px; text-align: center; }}
        .header h1 {{ margin: 0; font-size: 24px; }}
        .body {{ padding: 30px; color: #333333; line-height: 1.6; }}
        .otp-box {{ background-color: #f3f4f6; border: 2px dashed #2563eb; padding: 20px; text-align: center; margin: 20px 0; border-radius: 8px; }}
        .otp-code {{ font-size: 36px; font-weight: bold; color: #2563eb; letter-spacing: 8px; }}
        .footer {{ background-color: #f9fafb; padding: 20px; text-align: center; font-size: 12px; color: #6b7280; }}
        .warning {{ color: #dc2626; font-size: 13px; margin-top: 15px; }}
    </style>
</head>
<body>
    <div class='container'>
        <div class='header'>
            <h1>Freelance Job Finder</h1>
        </div>
        <div class='body'>
            <h2>Hi {userName}!</h2>
            <p>Welcome to Freelance Job Finder. To complete your registration, please verify your email using the OTP code below:</p>
            <div class='otp-box'>
                <div>Your verification code:</div>
                <div class='otp-code'>{otpCode}</div>
            </div>
            <p>This code is valid for <strong>{expiryMinutes} minutes</strong>.</p>
            <p class='warning'>⚠️ If you didn't request this code, please ignore this email.</p>
        </div>
        <div class='footer'>
            <p>© 2026 Freelance Job Finder. All rights reserved.</p>
            <p>This is an automated email, please do not reply.</p>
        </div>
    </div>
</body>
</html>";
    }

    public static string PasswordResetOtp(string userName, string otpCode, int expiryMinutes)
    {
        // Note: Make sure to replace 'https://yourwebsite.com/logo.png' with your actual logo URL.
        string logoUrl = "https://via.placeholder.com/200x50/4f46e5/ffffff?text=Freelance+Job+Finder";

        return $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
        /* Note: Double braces {{{{ }}}} are used in C# interpolated strings for CSS */
        body {{ 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background-color: #f3f4f6; 
            margin: 0; 
            padding: 20px; 
            -webkit-font-smoothing: antialiased;
        }}
        .container {{ 
            max-width: 550px; 
            margin: 0 auto; 
            background-color: #ffffff; 
            border-radius: 12px; 
            overflow: hidden; 
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.05); 
        }}
        .header {{ 
            padding: 30px 30px 20px; 
            text-align: center; 
            border-bottom: 1px solid #e5e7eb;
        }}
        .header img {{ 
            max-width: 180px; 
            height: auto; 
            display: block; 
            margin: 0 auto;
        }}
        .body {{ 
            padding: 30px; 
            color: #374151; 
            line-height: 1.6; 
            font-size: 16px;
        }}
        .body h2 {{ 
            color: #111827; 
            margin-top: 0; 
            font-size: 22px;
        }}
        .body p {{ 
            margin-bottom: 20px; 
        }}
        .otp-box {{ 
            background-color: #eef2ff; 
            border: 2px solid #c7d2fe; 
            padding: 25px; 
            text-align: center; 
            margin: 30px 0; 
            border-radius: 10px; 
        }}
        .otp-label {{ 
            font-size: 14px; 
            color: #4f46e5; 
            text-transform: uppercase; 
            letter-spacing: 1px; 
            font-weight: 600; 
            margin-bottom: 10px;
        }}
        .otp-code {{ 
            font-size: 40px; 
            font-weight: bold; 
            color: #4338ca; 
            letter-spacing: 10px; 
        }}
        .warning-box {{ 
            background-color: #fffbeb; 
            border-left: 4px solid #f59e0b; 
            padding: 15px; 
            margin-top: 30px; 
            font-size: 14px; 
            color: #92400e; 
            border-radius: 4px;
        }}
        .footer {{ 
            background-color: #f8fafc; 
            padding: 20px; 
            text-align: center; 
            font-size: 13px; 
            color: #64748b; 
            border-top: 1px solid #e5e7eb;
        }}
        .footer a {{
            color: #4f46e5;
            text-decoration: none;
        }}
    </style>
</head>
<body>
    <div class='container'>
        <div class='header'>
            <!-- Yahan apna actual logo URL lagayein -->
            <img src='{logoUrl}' alt='Freelance Job Finder Logo' />
        </div>
        <div class='body'>
            <h2>Hi {userName},</h2>
            <p>We received a request to reset your password for your <strong>Freelance Job Finder</strong> account.</p>
            <p>Please enter the verification code below in your app or browser to set up a new password:</p>
            
            <div class='otp-box'>
                <div class='otp-label'>Your Verification Code</div>
                <div class='otp-code'>{otpCode}</div>
            </div>
            
            <p>This code is secure and will expire in <strong>{expiryMinutes} minutes</strong>.</p>
            
            <div class='warning-box'>
                <strong>Didn't request this?</strong><br/>
                If you did not request a password reset, you can safely ignore this email. Your password will remain unchanged and your account is secure.
            </div>
        </div>
        <div class='footer'>
            <p>© 2026 Freelance Job Finder. All rights reserved.</p>
            <p>Need help? Visit our <a href='#'>Support Center</a>.</p>
            <p style='font-size: 11px; margin-top: 10px;'>This is an automated message, please do not reply.</p>
        </div>
    </div>
</body>
</html>";
    }
}