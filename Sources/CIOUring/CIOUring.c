//
//  CIOUring.c
//  
//
//  Maximilian Alexander
//

#include "include/CIOUring.h"
#include <stdlib.h>

struct io_uring_handle* iouring_create(unsigned entries) {
    struct io_uring_handle* handle = malloc(sizeof(struct io_uring_handle));
    if (!handle) {
        return NULL;
    }

    if (io_uring_queue_init(entries, &handle->ring, 0) < 0) {
        free(handle);
        return NULL;
    }

    return handle;
}

void iouring_destroy(struct io_uring_handle* handle) {
    io_uring_queue_exit(&handle->ring);
    free(handle);
}

int iouring_submit_and_wait(struct io_uring_handle* handle, unsigned wait_nr) {
    return io_uring_submit_and_wait(&handle->ring, wait_nr);
}

struct io_uring_sqe* iouring_get_sqe(struct io_uring_handle* handle) {
    return io_uring_get_sqe(&handle->ring);
}

void iouring_cqe_seen(struct io_uring_handle* handle, struct io_uring_cqe* cqe) {
    io_uring_cqe_seen(&handle->ring, cqe);
}
