require ["fileinto"];
# El spam que Rspamd marca (X-Spam-Flag: YES o X-Spam: Yes) va a la carpeta Junk en vez de a la bandeja de entrada
if anyof (header :contains "X-Spam-Flag" "YES", header :is "X-Spam" "Yes") {
  fileinto "Junk";
  stop;
}
