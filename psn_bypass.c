/*
 * NoTrack PSN Bypass - GoldHEN PRX Plugin
 * PS4 FW 14.00
 *
 * Redireciona todas as conexoes PSN para o servidor local no PC
 * Faz o PS4 pensar que esta conectado na PSN
 *
 * Compilar com o SDK GoldHEN:
 *   clang -target x86_64-pc-freebsd12-ps4 -fPIC -shared -o psn_bypass.prx psn_bypass.c
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <ps4/kernel.h>
#include <ps4/pthread.h>
#include <ps4/sce_module.h>
#include <ps4/sce_sysmodule.h>

/* ============================================================
 * CONFIGURACAO - ALTERE AQUI O IP DO SEU SERVIDOR PC
 * ============================================================ */
#define SERVER_IP       "26.16.0.7"   // <<< ALTERE para o IP do seu PC
#define SERVER_PORT     80
#define DNS_PORT        53

/* Dominios PSN que serao redirecionados */
static const char *psn_domains[] = {
    "playstation.net",
    "psn.net",
    "sonyentertainmentnetwork.com",
    "np.ac.playstation.net",
    "npsp.ac.playstation.net",
    "np.community.playstation.net",
    "np.prod.ac.playstation.net",
    "auth.api.sony.com",
    "auth.np.ac.playstation.net",
    "grp.np.community.playstation.net",
    "prof.np.community.playstation.net",
    "ps4.np.community.playstation.net",
    "f.np.community.playstation.net",
    "api.sony.com",
    "ps5.np.community.playstation.net",
    "store.playstation.com",
    NULL
};

/* IP do servidor em formato de bytes */
static struct in_addr server_addr;
static int server_initialized = 0;

/* Mutex para thread safety */
static pthread_mutex_t dns_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ============================================================
 * Hook da funcao getaddrinfo - redireciona dominios PSN
 * ============================================================ */

/* Ponteiro para a funcao original */
typedef int (*getaddrinfo_func_t)(const char *node, const char *service,
                                  const struct addrinfo *hints,
                                  struct addrinfo **res);
static getaddrinfo_func_t original_getaddrinfo = NULL;

/* Nosso hook */
int hook_getaddrinfo(const char *node, const char *service,
                     const struct addrinfo *hints,
                     struct addrinfo **res) {
    int ret;
    
    /* Verifica se o dominio deve ser redirecionado */
    if (node != NULL) {
        for (int i = 0; psn_domains[i] != NULL; i++) {
            if (strstr(node, psn_domains[i]) != NULL) {
                /* Dominio PSN detectado! Redirecionar para o servidor local */
                struct addrinfo *ai = (struct addrinfo *)malloc(sizeof(struct addrinfo));
                struct sockaddr_in *sa = (struct sockaddr_in *)malloc(sizeof(struct sockaddr_in));
                
                if (ai == NULL || sa == NULL) {
                    if (ai) free(ai);
                    if (sa) free(sa);
                    break;
                }
                
                memset(ai, 0, sizeof(struct addrinfo));
                memset(sa, 0, sizeof(struct sockaddr_in));
                
                ai->ai_family = AF_INET;
                ai->ai_socktype = hints ? hints->ai_socktype : SOCK_STREAM;
                ai->ai_protocol = hints ? hints->ai_protocol : IPPROTO_TCP;
                ai->ai_addrlen = sizeof(struct sockaddr_in);
                ai->ai_addr = (struct sockaddr *)sa;
                ai->ai_next = NULL;
                ai->ai_canonname = NULL;
                
                sa->sin_family = AF_INET;
                sa->sin_port = htons(SERVER_PORT);
                sa->sin_addr = server_addr;
                
                *res = ai;
                
                /* Log no console do PS4 */
                sceKernelDebugOut(0, "[NoTrack] PSN Bypass: %s -> %s:%d\n",
                                  node, SERVER_IP, SERVER_PORT);
                
                return 0; /* Sucesso */
            }
        }
    }
    
    /* Nao e PSN, chama funcao original */
    if (original_getaddrinfo) {
        return original_getaddrinfo(node, service, hints, res);
    }
    
    /* Fallback se nao tiver hook */
    return getaddrinfo(node, service, hints, res);
}

/* ============================================================
 * Hook de DNS - intercepta pacotes DNS UDP
 * ============================================================ */

/* Hook do socket para interceptar DNS */
typedef int (*socket_func_t)(int domain, int type, int protocol);
static socket_func_t original_socket = NULL;

int hook_socket(int domain, int type, int protocol) {
    int fd = original_socket ? original_socket(domain, type, protocol)
                             : socket(domain, type, protocol);
    
    if (fd >= 0 && domain == AF_INET && type == SOCK_DGRAM && protocol == 0) {
        /* Potencial socket DNS - salva para monitoramento */
        sceKernelDebugOut(0, "[NoTrack] Socket UDP criado: fd=%d\n", fd);
    }
    
    return fd;
}

/* ============================================================
 * Hook sendto - intercepta pacotes DNS enviados
 * ============================================================ */

typedef ssize_t (*sendto_func_t)(int sockfd, const void *buf, size_t len,
                                 int flags, const struct sockaddr *dest_addr,
                                 socklen_t addrlen);
static sendto_func_t original_sendto = NULL;

ssize_t hook_sendto(int sockfd, const void *buf, size_t len,
                    int flags, const struct sockaddr *dest_addr,
                    socklen_t addrlen) {
    
    /* Verifica se e um pacote DNS (porta 53) */
    if (dest_addr != NULL && dest_addr->sa_family == AF_INET) {
        const struct sockaddr_in *dest = (const struct sockaddr_in *)dest_addr;
        
        if (ntohs(dest->sin_port) == 53) {
            /* Pacote DNS detectado - redireciona para nosso servidor */
            struct sockaddr_in our_dns;
            memset(&our_dns, 0, sizeof(our_dns));
            our_dns.sin_family = AF_INET;
            our_dns.sin_port = htons(53);
            our_dns.sin_addr = server_addr;
            
            sceKernelDebugOut(0, "[NoTrack] DNS query redirecionada para %s\n", SERVER_IP);
            
            if (original_sendto) {
                return original_sendto(sockfd, buf, len, flags,
                                       (struct sockaddr *)&our_dns, sizeof(our_dns));
            }
        }
    }
    
    if (original_sendto) {
        return original_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
    }
    
    return sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

/* ============================================================
 * Hook connect - redireciona conexoes TCP para o servidor
 * ============================================================ */

typedef int (*connect_func_t)(int sockfd, const struct sockaddr *addr,
                              socklen_t addrlen);
static connect_func_t original_connect = NULL;

int hook_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    /* Deixa a resolucao de DNS (getaddrinfo) fazer o trabalho */
    /* Mas podemos forcar redirecionamento aqui se necessario */
    
    if (original_connect) {
        return original_connect(sockfd, addr, addrlen);
    }
    
    return connect(sockfd, addr, addrlen);
}

/* ============================================================
 * Inicializacao do plugin
 * ============================================================ */

__attribute__((constructor))
static void psn_bypass_init(void) {
    sceKernelDebugOut(0, "\n");
    sceKernelDebugOut(0, "========================================\n");
    sceKernelDebugOut(0, "  NoTrack PSN Bypass v1.0\n");
    sceKernelDebugOut(0, "  PS4 FW 14.00 | GoldHEN PRX\n");
    sceKernelDebugOut(0, "========================================\n");
    
    /* Converte o IP do servidor */
    if (inet_aton(SERVER_IP, &server_addr) == 0) {
        sceKernelDebugOut(0, "[NoTrack] ERRO: IP invalido: %s\n", SERVER_IP);
        return;
    }
    
    server_initialized = 1;
    
    sceKernelDebugOut(0, "[NoTrack] Servidor PSN: %s:%d\n", SERVER_IP, SERVER_PORT);
    sceKernelDebugOut(0, "[NoTrack] Dominios PSN bloqueados: %d\n",
                      sizeof(psn_domains) / sizeof(psn_domains[0]) - 1);
    
    /* Aqui seria instalado o hook via GoldHEN */
    /* Na pratica, o GoldHEN fornece uma API de hooking */
    /* Exemplo conceitual: */
    /* install_hook(sceLibc_getaddrinfo, hook_getaddrinfo, (void**)&original_getaddrinfo); */
    
    sceKernelDebugOut(0, "[NoTrack] Plugin carregado com sucesso!\n");
    sceKernelDebugOut(0, "========================================\n\n");
}

__attribute__((destructor))
static void psn_bypass_fini(void) {
    sceKernelDebugOut(0, "[NoTrack] PSN Bypass descarregado.\n");
}

/* ============================================================
 * Module info obrigatorio para PRX
 * ============================================================ */

int module_start(SceModule *module) {
    psn_bypass_init();
    return 0;
}

int module_stop(SceModule *module) {
    psn_bypass_fini();
    return 0;
}