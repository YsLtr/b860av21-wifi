/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _RTW_COMPAT_H
#define _RTW_COMPAT_H

#include <linux/string.h>
#include <linux/version.h>
#include <linux/etherdevice.h>

/* Keep the original return value (source length), including truncation. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
#ifndef strlcpy
static inline size_t rtw_strlcpy(char *dst, const char *src, size_t size)
{
	size_t ret = strlen(src);
	if (size) {
		size_t len = (ret >= size) ? size - 1 : ret;
		memcpy(dst, src, len);
		dst[len] = '\0';
	}
	return ret;
}
#define strlcpy rtw_strlcpy
#endif
#endif

static inline void rtw_eth_hw_addr_set(struct net_device *dev, const void *addr)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
	eth_hw_addr_set(dev, addr);
#else
	memcpy(dev->dev_addr, addr, ETH_ALEN);
#endif
}

#endif
