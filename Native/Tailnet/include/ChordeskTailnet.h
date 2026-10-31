#ifndef CHORDESK_TAILNET_H
#define CHORDESK_TAILNET_H
// Returned JSON strings are owned by the caller; release with free().
char *CRStart(char *directory, char *hostname);
char *CRStatus(void);
char *CRLogin(void);
char *CRStop(void);
char *CRLogout(void);
char *CRForward(int localhostPort);
char *CRStopForward(void);
char *CRDial(char *host, int port);
char *CRCloseDial(int identifier);
#endif
