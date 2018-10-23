# ADOS Extension: Install SSL and custom domains

## How to use:
1. Upload a .PFX file as a secure file in your projects library.
2. Create a secret variable with the password of that .PFX file.
3. Add the Download Secure File to the release definition to download the .PFX file to your agent.
4. Add the Install SSL and custom domains step after the Download Secure File step.
5. Configure the step with the following settings:
    - AzureRM subscription: The service connection to your Azure subscription.
    - AppServiceName: The name of the App Service to which the certificate and custom domains must be installed.
    - CertificateFileName: The name of the secure file containing the certificate.
    - CertificatePassword: The password of the certificate.
    - CustomDomains: The list of custom domains to be attached, use comma's to separate multiple domains.
    - ResourceGroupName: The name of the resource group in which the App Service exists in Azure.
